module InventoryRefresh
  class Persister
    require 'json'
    require 'yaml'

    attr_reader :manager, :target, :collections

    attr_accessor :refresh_state_uuid, :refresh_state_part_uuid, :total_parts, :sweep_scope, :retry_count, :retry_max

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
        self.define_collections_reader(method_name)
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
    def define_collections_reader(collection_key)
      define_singleton_method(collection_key) do
        collections[collection_key]
      end
    end

    def inventory_collection_builder
      ::InventoryRefresh::InventoryCollection::Builder
    end

    # Persists InventoryCollection objects into the DB
    def persist!
      InventoryRefresh::SaveInventory.save_inventory(manager, inventory_collections)
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
                collection.all_manager_uuids.nil? &&
                collection.skeletal_primary_index.index_data.blank?

        collection.to_hash
      end.compact

      {
        :refresh_state_uuid      => refresh_state_uuid,
        :refresh_state_part_uuid => refresh_state_part_uuid,
        :retry_count             => retry_count,
        :retry_max               => retry_max,
        :total_parts             => total_parts,
        :sweep_scope             => sweep_scope,
        :collections             => collections_data,
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
          persister.retry_count             = persister_data['retry_count']
          persister.retry_max               = persister_data['retry_max']
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

    def saver_strategy
      :default
    end

    # Persisters for targeted refresh can override to true
    def targeted?
      false
    end

    def assert_graph_integrity?
      false
    end

    # @return [Hash] kwargs shared for all InventoryCollection objects
    def shared_options
      {
        :saver_strategy         => saver_strategy,
        :strategy               => strategy,
        :targeted               => targeted?,
        :parent                 => manager.presence,
        :assert_graph_integrity => assert_graph_integrity?,
      }
    end
  end
end
