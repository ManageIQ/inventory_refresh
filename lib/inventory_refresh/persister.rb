require "inventory_refresh/inventory_collection"
require "inventory_refresh/logging"
require "inventory_refresh/save_inventory"

module InventoryRefresh
  class Persister
    include InventoryRefresh::Logging
    include InventoryRefresh::SaveCollection::Saver::SqlHelper

    require 'json'
    require 'yaml'

    attr_reader :manager, :target, :collections

    attr_accessor :refresh_state_uuid, :refresh_state_part_uuid, :total_parts, :sweep_scope

    # @param manager [ManageIQ::Providers::BaseManager] A manager object
    # @param target [Object] A refresh Target object
    def initialize(manager, target = nil)
      @manager = manager
      @target  = target

      @collections = {}

      initialize_inventory_collections
    end

    # Interface for creating InventoryCollection under @collections
    #
    # @param builder_class    [ManageIQ::Providers::Inventory::Persister::Builder] or subclasses
    # @param collection_name  [Symbol || Array] used as InventoryCollection:association
    # @param extra_properties [Hash]   props from InventoryCollection.initialize list
    #         - adds/overwrites properties added by builder
    #
    # @param settings [Hash] builder settings
    #         - @see ManageIQ::Providers::Inventory::Persister::Builder.default_options
    #         - @see make_builder_settings()
    #
    # @example
    #   add_collection(:vms, ManageIQ::Providers::Inventory::Persister::Builder::CloudManager) do |builder|
    #     builder.add_properties(
    #       :strategy => :local_db_cache_all,
    #     )
    #   )
    #
    # @see documentation https://github.com/ManageIQ/guides/tree/master/providers/persister/inventory_collections.md
    #
    def add_collection(collection_name, builder_class = inventory_collection_builder, extra_properties = {}, settings = {}, &block)
      builder = builder_class.prepare_data(collection_name,
                                           self.class,
                                           builder_settings(settings),
                                           &block)

      builder.add_properties(extra_properties) if extra_properties.present?

      builder.add_properties({:manager_uuids => target.try(:references, collection_name) || []}, :if_missing) if targeted?

      builder.evaluate_lambdas!(self)

      collections[collection_name] = builder.to_inventory_collection
    end

    # @return [Array<InventoryRefresh::InventoryCollection>] array of InventoryCollection objects of the persister
    def inventory_collections
      collections.values
    end

    # @return [Array<Symbol>] array of InventoryCollection object names of the persister
    def inventory_collections_names
      collections.keys
    end

    # @return [InventoryRefresh::InventoryCollection] returns a defined InventoryCollection or undefined method
    def method_missing(method_name, *arguments, &block)
      if inventory_collections_names.include?(method_name)
        self.class.define_collections_reader(method_name)
        send(method_name)
      else
        super
      end
    end

    # @return [Boolean] true if InventoryCollection with passed method_name name is defined
    def respond_to_missing?(method_name, _include_private = false)
      inventory_collections_names.include?(method_name) || super
    end

    # Defines a new attr reader returning InventoryCollection object
    def self.define_collections_reader(collection_key)
      define_method(collection_key) do
        collections[collection_key]
      end
    end

    def inventory_collection_builder
      ::InventoryRefresh::InventoryCollection::Builder
    end

    # Persists InventoryCollection objects into the DB or sweeps inactive records based on :last_seen_at attribute,
    # if the :total_parts attribute was passed
    #
    # @return [Boolean] If true, the job wasn't finished and should be re-queued
    def persist!
      if total_parts
        sweep_inactive_records!
      else
        persist_collections!
      end
    end

    # Returns serialized Persisted object to JSON
    # @return [String] serialized Persisted object to JSON
    def to_json
      JSON.dump(to_hash)
    end

    # @return [Hash] entire Persister object serialized to hash
    def to_hash
      collections_data = collections.map do |_, collection|
        next if collection.data.blank? &&
          collection.targeted_scope.primary_references.blank? &&
          collection.all_manager_uuids.nil? &&
          collection.skeletal_primary_index.index_data.blank?

        collection.to_hash
      end.compact

      {
        :collections => collections_data
      }
    end

    class << self
      # Returns Persister object loaded from a passed JSON
      #
      # @param json_data [String] input JSON data
      # @return [ManageIQ::Providers::Inventory::Persister] Persister object loaded from a passed JSON
      def from_json(json_data, manager, target = nil)
        from_hash(JSON.parse(json_data), manager, target)
      end

      # Returns Persister object built from serialized data
      #
      # @param persister_data [Hash] serialized Persister object in hash
      # @return [ManageIQ::Providers::Inventory::Persister] Persister object built from serialized data
      def from_hash(persister_data, manager, target = nil)
        # TODO(lsmola) we need to pass serialized targeted scope here
        target ||= InventoryRefresh::TargetCollection.new(:manager => manager)

        new(manager, target).tap do |persister|
          persister_data['collections'].each do |collection|
            inventory_collection = persister.collections[collection['name'].try(:to_sym)]
            raise "Unrecognized InventoryCollection name: #{inventory_collection}" if inventory_collection.blank?

            inventory_collection.from_hash(collection, persister.collections)
          end

          persister.refresh_state_uuid      = persister_data['refresh_state_uuid']
          persister.refresh_state_part_uuid = persister_data['refresh_state_part_uuid']
          persister.total_parts             = persister_data['total_parts']
          persister.sweep_scope             = persister_data['sweep_scope']
        end
      end
    end

    protected

    def initialize_inventory_collections
      # can be implemented in a subclass
    end

    # @param extra_settings [Hash]
    #   :auto_inventory_attributes
    #     - auto creates inventory_object_attributes from target model_class setters
    #     - attributes used in InventoryObject.add_attributes
    #   :without_model_class
    #     - if false and no model_class derived or specified, throws exception
    #     - doesn't try to derive model class automatically
    #     - @see method ManageIQ::Providers::Inventory::Persister::Builder.auto_model_class
    def builder_settings(extra_settings = {})
      opts = inventory_collection_builder.default_options

      opts[:shared_properties]         = shared_options
      opts[:auto_inventory_attributes] = true
      opts[:without_model_class]       = false

      opts.merge(extra_settings)
    end

    def strategy
      nil
    end

    # Persisters for targeted refresh can override to true
    def targeted?
      false
    end

    # @return [Hash] kwargs shared for all InventoryCollection objects
    def shared_options
      {
        :strategy => strategy,
        :targeted => targeted?,
        :parent   => manager.presence
      }
    end

    private

    def upsert_refresh_state_records(status: nil, refresh_state_status: nil, error_message: nil)
      return unless refresh_state_uuid

      refresh_states_inventory_collection = ::InventoryRefresh::InventoryCollection.new(
        :manager_ref                 => [:uuid],
        :saver_strategy              => :concurrent_safe_batch,
        :parent                      => manager,
        :association                 => :refresh_states,
        :create_only                 => true,
        :model_class                 => RefreshState,
        :inventory_object_attributes => [:ems_id, :uuid, :status, :source_id, :tenant_id]
      )

      refresh_state_parts_inventory_collection = ::InventoryRefresh::InventoryCollection.new(
        :manager_ref                 => [:refresh_state, :uuid],
        :saver_strategy              => :concurrent_safe_batch,
        :parent                      => manager,
        :association                 => :refresh_state_parts,
        :create_only                 => true,
        :model_class                 => RefreshStatePart,
        :inventory_object_attributes => [:refresh_state, :uuid, :status, :error_message]
      )

      if refresh_state_status
        refresh_states_inventory_collection.build(RefreshState.owner_ref(manager).merge(
          :uuid   => refresh_state_uuid,
          :status => refresh_state_status,
        ))
      end

      if status
        refresh_state_part_data = {
          :uuid          => refresh_state_part_uuid,
          :refresh_state => refresh_states_inventory_collection.lazy_find(
            RefreshState.owner_ref(manager).merge({:uuid => refresh_state_uuid})
          ),
          :status        => status
        }
        refresh_state_part_data[:error_message] = error_message if error_message

        refresh_state_parts_inventory_collection.build(refresh_state_part_data)
      end

      InventoryRefresh::SaveInventory.save_inventory(
        manager, [refresh_states_inventory_collection, refresh_state_parts_inventory_collection]
      )
    end

    # Persists InventoryCollection objects into the DB
    #
    # @return [Boolean] If true, the job wasn't finished and should be re-queued
    def persist_collections!
      upsert_refresh_state_records(:status => :started, :refresh_state_status => :started)

      InventoryRefresh::SaveInventory.save_inventory(manager, inventory_collections)

      upsert_refresh_state_records(:status => :finished)

      false
    rescue => e
      upsert_refresh_state_records(:status => :error, :error_message => e.message.truncate(150))

      raise(e)
    end

    # Sweeps inactive records based on :last_seen_at attribute
    #
    # @return [Boolean] If true, the job wasn't finished and should be re-queued
    def sweep_inactive_records!
      refresh_state = manager.refresh_states.find_by(:uuid => refresh_state_uuid)
      unless refresh_state
        upsert_refresh_state_records(:refresh_state_status => :started)

        refresh_state = manager.refresh_states.find_by!(:uuid => refresh_state_uuid)
      end

      refresh_state.update_attributes!(:status => :waiting_for_refresh_state_parts, :total_parts => total_parts, :sweep_scope => sweep_scope)

      if total_parts == refresh_state.refresh_state_parts.count
        start_sweeping!(refresh_state)
      else
        return wait_for_sweeping!(refresh_state)
      end

      false
    rescue => e
      refresh_state.update_attributes!(:status => :error, :error_message => "Error while sweeping: #{e.message.truncate(150)}")

      raise(e)
    end

    def start_sweeping!(refresh_state)
      error_count = refresh_state.refresh_state_parts.where(:status => :error).count

      if error_count > 0
        refresh_state.update_attributes!(:status => :error, :error_message => "Error when saving one or more parts, sweeping can't be done.")
      else
        refresh_state.update_attributes!(:status => :sweeping)
        InventoryRefresh::SaveInventory.sweep_inactive_records(manager, inventory_collections, refresh_state)
        refresh_state.update_attributes!(:status => :finished)
      end
    end

    def wait_for_sweeping!(refresh_state)
      sweep_retry_count = refresh_state.sweep_retry_count + 1

      if sweep_retry_count > sweep_retry_count_limit
        refresh_state.update_attributes!(
          :status => :error,
          :error_message => "Sweep retry count limit of #{sweep_retry_count_limit} was reached.")

        false
      else
        refresh_state.update_attributes!(:status => :waiting_for_refresh_state_parts, :sweep_retry_count => sweep_retry_count)

        # When returning true the Persitor worker should requeue the the same Persister job
        true
      end
    end

    def sweep_retry_count_limit
      100
    end
  end
end
