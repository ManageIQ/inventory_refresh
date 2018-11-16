require "inventory_refresh/logging"
require "inventory_refresh/save_collection/saver/retention_helper"

module InventoryRefresh::SaveCollection
  class Sweeper < InventoryRefresh::SaveCollection::Base
    class << self
      # Sweeps inactive records based on :last_seen_on and :refresh_start timestamps. All records having :last_seen_on
      # lower than :refresh_start or nil will be archived/deleted.
      #
      # @param ems [ExtManagementSystem] manager owning the inventory_collections
      # @param inventory_collections [Array<InventoryRefresh::InventoryCollection>] array of InventoryCollection objects
      #        for sweeping
      # @param refresh_state [ActiveRecord] Record of :refresh_states
      def sweep(ems, inventory_collections, refresh_state)
        inventory_collections.each do |inventory_collection|
          next unless inventory_collection.supports_column?(:last_seen_at) && inventory_collection.parallel_safe?
          # Ignoring full refresh and db load only ICs
          next unless inventory_collection.strategy == :local_db_find_missing_references
          # If sweep_scope is defined, lets validate that
          next unless in_scope?(inventory_collection, refresh_state.sweep_scope)

          self.new(inventory_collection, refresh_state).sweep
        end
      end

      def in_scope?(inventory_collection, sweep_scope)
        return true unless sweep_scope

        if sweep_scope.kind_of?(Array)
          return true if sweep_scope.include?(inventory_collection&.name&.to_s)
        end

        false
      end
    end

    include InventoryRefresh::SaveCollection::Saver::RetentionHelper

    attr_reader :inventory_collection, :refresh_state, :model_class, :primary_key

    def initialize(inventory_collection, refresh_state)
      @inventory_collection = inventory_collection
      @refresh_state        = refresh_state

      @model_class            = inventory_collection.model_class
      @primary_key            = @model_class.primary_key
    end

    def sweep
      refresh_start = refresh_state.created_at
      raise "Couldn't load :created_at out of RefreshState record: #{refresh_state}" unless refresh_start

      table       = model_class.arel_table
      date_field  = table[:last_seen_at]
      all_entities_query = inventory_collection.full_collection_for_comparison
      all_entities_query.active if inventory_collection.retention_strategy == :archive

      query       = all_entities_query
                      .where(date_field.lt(refresh_start)).or(all_entities_query.where(:last_seen_at => nil))
                      .select(table[:id])

      query.find_in_batches do |batch|
        destroy_records!(batch)
      end
    end
  end
end
