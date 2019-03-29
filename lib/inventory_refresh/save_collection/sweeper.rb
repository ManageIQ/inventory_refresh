require "inventory_refresh/exception"
require "inventory_refresh/logging"
require "inventory_refresh/save_collection/saver/retention_helper"
require "inventory_refresh/inventory_collection/index/type/local_db"

module InventoryRefresh::SaveCollection
  class Sweeper < InventoryRefresh::SaveCollection::Base
    class << self
      # Sweeps inactive records based on :last_seen_on and :refresh_start timestamps. All records having :last_seen_on
      # lower than :refresh_start or nil will be archived/deleted.
      #
      # @param _ems [ActiveRecord] Manager owning the inventory_collections
      # @param inventory_collections [Array<InventoryRefresh::InventoryCollection>] Array of InventoryCollection objects
      #        for sweeping
      # @param sweep_scope [Array<String, Symbol, Hash>] Array of inventory collection names marking sweep. Or for
      #        targeted sweeping it's array of hashes, where key is inventory collection name pointing to an array of
      #        identifiers of inventory objects we want to target for sweeping.
      # @param refresh_state [ActiveRecord] Record of :refresh_states
      def sweep(_ems, inventory_collections, sweep_scope, refresh_state)
        scope_set = build_scope_set(sweep_scope)

        inventory_collections.each do |inventory_collection|
          next unless sweep_possible?(inventory_collection, scope_set)

          new(inventory_collection, refresh_state).sweep
        end
      end

      def sweep_possible?(inventory_collection, scope_set)
        inventory_collection.supports_column?(:last_seen_at) && inventory_collection.parallel_safe? &&
          in_scope?(inventory_collection, scope_set)
      end

      def in_scope?(inventory_collection, scope_set)
        scope_set.include?(inventory_collection&.name)
      end

      def build_scope_set(sweep_scope)
        return [] unless sweep_scope

        if sweep_scope.kind_of?(Array)
          sweep_scope.map(&:to_sym).to_set
        elsif sweep_scope.kind_of?(Hash)
          sweep_scope.keys.map(&:to_sym).to_set
        else
          []
        end
      end
    end

    include InventoryRefresh::SaveCollection::Saver::RetentionHelper

    attr_reader :inventory_collection, :refresh_state, :sweep_scope, :model_class, :primary_key

    delegate :inventory_object_lazy?,
             :inventory_object?,
             :to => :inventory_collection

    def initialize(inventory_collection, refresh_state)
      @inventory_collection = inventory_collection

      @refresh_state = refresh_state
      @sweep_scope   = refresh_state.sweep_scope

      @model_class = inventory_collection.model_class
      @primary_key = @model_class.primary_key
    end

    def apply_targeted_sweep_scope(all_entities_query)
      if sweep_scope.kind_of?(Hash)
        scope = sweep_scope[inventory_collection.name]
        return all_entities_query if scope.nil? || scope.empty?

        # Scan the scope to find all references, so we can load them from DB in batches
        scan_sweep_scope!(scope)

        scope_keys = Set.new
        conditions = scope.map { |x| InventoryRefresh::InventoryObject.attributes_with_keys(x, inventory_collection, scope_keys) }
        assert_conditions!(conditions, scope_keys)

        all_entities_query.where(inventory_collection.build_multi_selection_condition(conditions, scope_keys))
      else
        all_entities_query
      end
    end

    def loadable?(value)
      inventory_object_lazy?(value) || inventory_object?(value)
    end

    def scan_sweep_scope!(scope)
      scope.each do |sc|
        sc.each_value do |value|
          next unless loadable?(value)

          value_inventory_collection = value.inventory_collection
          value_inventory_collection.add_reference(value.reference, :key => value.key)
        end
      end
    end

    def assert_conditions!(conditions, scope_keys)
      conditions.each do |cond|
        assert_uniform_keys!(cond, scope_keys)
        assert_non_existent_keys!(cond)
      end
    end

    def assert_uniform_keys!(cond, scope_keys)
      return if (diff = (scope_keys - cond.keys.to_set)).empty?

      raise(InventoryRefresh::Exception::SweeperNonUniformScopeKeyFoundError,
            "Sweeping scope for #{inventory_collection} contained non uniform keys. All keys for the"\
            "scope must be the same, it's possible to send multiple sweeps with different key set. Missing keys"\
            " for a scope were: #{diff.to_a}")
    end

    def assert_non_existent_keys!(cond)
      return if (diff = (cond.keys.to_set - inventory_collection.all_column_names)).empty?

      raise(InventoryRefresh::Exception::SweeperNonExistentScopeKeyFoundError,
            "Sweeping scope for #{inventory_collection} contained keys that are not columns: #{diff.to_a}")
    end

    def sweep
      refresh_start = refresh_state.created_at
      raise "Couldn't load :created_at out of RefreshState record: #{refresh_state}" unless refresh_start

      table       = model_class.arel_table
      date_field  = table[:last_seen_at]
      all_entities_query = inventory_collection.full_collection_for_comparison
      all_entities_query.active if inventory_collection.retention_strategy == :archive

      all_entities_query = apply_targeted_sweep_scope(all_entities_query)

      query = all_entities_query
              .where(date_field.lt(refresh_start)).or(all_entities_query.where(:last_seen_at => nil))
              .select(table[:id])

      query.find_in_batches do |batch|
        destroy_records!(batch)
      end
    end
  end
end
