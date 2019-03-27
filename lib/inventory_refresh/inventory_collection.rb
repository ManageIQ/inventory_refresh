require "inventory_refresh/inventory_collection/builder"
require "inventory_refresh/inventory_collection/data_storage"
require "inventory_refresh/inventory_collection/index/proxy"
require "inventory_refresh/inventory_collection/reference"
require "inventory_refresh/inventory_collection/references_storage"
require "inventory_refresh/inventory_collection/scanner"
require "inventory_refresh/inventory_collection/serialization"
require "inventory_refresh/inventory_collection/unconnected_edge"
require "inventory_refresh/inventory_collection/helpers/initialize_helper"
require "inventory_refresh/inventory_collection/helpers/associations_helper"
require "inventory_refresh/inventory_collection/helpers/questions_helper"

require "active_support/core_ext/module/delegation"

module InventoryRefresh
  # For more usage examples please follow spec examples in
  # * spec/models/inventory_refresh/save_inventory/single_inventory_collection_spec.rb
  # * spec/models/inventory_refresh/save_inventory/acyclic_graph_of_inventory_collections_spec.rb
  # * spec/models/inventory_refresh/save_inventory/graph_of_inventory_collections_spec.rb
  # * spec/models/inventory_refresh/save_inventory/graph_of_inventory_collections_targeted_refresh_spec.rb
  # * spec/models/inventory_refresh/save_inventory/strategies_and_references_spec.rb
  #
  # @example storing Vm model data into the DB
  #
  #   @ems = ManageIQ::Providers::BaseManager.first
  #   puts @ems.vms.collect(&:ems_ref) # => []
  #
  #   # Init InventoryCollection
  #   vms_inventory_collection = ::InventoryRefresh::InventoryCollection.new(
  #     :model_class => ManageIQ::Providers::CloudManager::Vm, :parent => @ems, :association => :vms
  #   )
  #
  #   # Fill InventoryCollection with data
  #   # Starting with no vms, lets add vm1 and vm2
  #   vms_inventory_collection.build(:ems_ref => "vm1", :name => "vm1")
  #   vms_inventory_collection.build(:ems_ref => "vm2", :name => "vm2")
  #
  #   # Save InventoryCollection to the db
  #   InventoryRefresh::SaveInventory.save_inventory(@ems, [vms_inventory_collection])
  #
  #   # The result in the DB is that vm1 and vm2 were created
  #   puts @ems.vms.collect(&:ems_ref) # => ["vm1", "vm2"]
  #
  # @example In another refresh, vm1 does not exist anymore and vm3 was added
  #   # Init InventoryCollection
  #   vms_inventory_collection = ::InventoryRefresh::InventoryCollection.new(
  #     :model_class => ManageIQ::Providers::CloudManager::Vm, :parent => @ems, :association => :vms
  #   )
  #
  #   # Fill InventoryCollection with data
  #   vms_inventory_collection.build(:ems_ref => "vm2", :name => "vm2")
  #   vms_inventory_collection.build(:ems_ref => "vm3", :name => "vm3")
  #
  #   # Save InventoryCollection to the db
  #   InventoryRefresh::SaveInventory.save_inventory(@ems, [vms_inventory_collection])
  #
  #   # The result in the DB is that vm1 was deleted, vm2 was updated and vm3 was created
  #   puts @ems.vms.collect(&:ems_ref) # => ["vm2", "vm3"]
  #
  class InventoryCollection
    # @return [Boolean] A true value marks that we collected all the data of the InventoryCollection,
    #         meaning we also collected all the references.
    attr_accessor :data_collection_finalized

    # @return [InventoryRefresh::InventoryCollection::DataStorage] An InventoryCollection encapsulating all data with
    #         indexes
    attr_accessor :data_storage

    # @return [Boolean] true if this collection is already saved into the DB. E.g. InventoryCollections with
    #   DB only strategy are marked as saved. This causes InventoryCollection not being a dependency for any other
    #   InventoryCollection, since it is already persisted into the DB.
    attr_accessor :saved

    # If present, InventoryCollection switches into delete_complement mode, where it will
    # delete every record from the DB, that is not present in this list. This is used for the batch processing,
    # where we don't know which InventoryObject should be deleted, but we know all manager_uuids of all
    # InventoryObject objects that exists in the provider.
    #
    # @return [Array, nil] nil or a list of all :manager_uuids that are present in the Provider's InventoryCollection.
    attr_accessor :all_manager_uuids

    # @return [Array, nil] Scope for applying :all_manager_uuids
    attr_accessor :all_manager_uuids_scope

    # @return [String] Timestamp in UTC before fetching :all_manager_uuids
    attr_accessor :all_manager_uuids_timestamp

    # @return [Set] A set of InventoryCollection objects that depends on this InventoryCollection object.
    attr_accessor :dependees

    # @return [Array<Symbol>] @see #parent_inventory_collections documentation of InventoryCollection.new's initialize_ic_relations()
    #   parameters
    attr_accessor :parent_inventory_collections

    attr_reader :model_class, :strategy, :attributes_blacklist, :attributes_whitelist, :custom_save_block, :parent,
                :internal_attributes, :delete_method, :dependency_attributes, :manager_ref, :create_only,
                :association, :complete, :update_only, :transitive_dependency_attributes, :check_changed, :arel,
                :inventory_object_attributes, :name, :saver_strategy, :default_values,
                :targeted_arel, :targeted, :manager_ref_allowed_nil, :use_ar_object,
                :created_records, :updated_records, :deleted_records, :retention_strategy,
                :custom_reconnect_block, :batch_extra_attributes, :references_storage, :unconnected_edges,
                :assert_graph_integrity

    delegate :<<,
             :build,
             :build_partial,
             :data,
             :each,
             :find_or_build,
             :find_or_build_by,
             :from_hash,
             :index_proxy,
             :push,
             :size,
             :to_a,
             :to_hash,
             :to => :data_storage

    delegate :add_reference,
             :attribute_references,
             :build_reference,
             :references,
             :build_stringified_reference,
             :build_stringified_reference_for_record,
             :to => :references_storage

    delegate :find,
             :find_by,
             :lazy_find,
             :lazy_find_by,
             :named_ref,
             :primary_index,
             :reindex_secondary_indexes!,
             :skeletal_primary_index,
             :to => :index_proxy

    delegate :table_name,
             :to => :model_class

    include ::InventoryRefresh::InventoryCollection::Helpers::AssociationsHelper
    include ::InventoryRefresh::InventoryCollection::Helpers::InitializeHelper
    include ::InventoryRefresh::InventoryCollection::Helpers::QuestionsHelper

    # @param [Hash] properties - see init methods for params description
    def initialize(properties = {})
      init_basic_properties(properties[:association],
                            properties[:model_class],
                            properties[:name],
                            properties[:parent])

      init_flags(properties[:complete],
                 properties[:create_only],
                 properties[:check_changed],
                 properties[:update_only],
                 properties[:use_ar_object],
                 properties[:targeted],
                 properties[:assert_graph_integrity])

      init_strategies(properties[:strategy],
                      properties[:saver_strategy],
                      properties[:retention_strategy],
                      properties[:delete_method])

      init_references(properties[:manager_ref],
                      properties[:manager_ref_allowed_nil],
                      properties[:secondary_refs])

      init_all_manager_uuids(properties[:all_manager_uuids],
                             properties[:all_manager_uuids_scope],
                             properties[:all_manager_uuids_timestamp])

      init_ic_relations(properties[:dependency_attributes],
                        properties[:parent_inventory_collections])

      init_arels(properties[:arel],
                 properties[:targeted_arel])

      init_custom_procs(properties[:custom_save_block],
                        properties[:custom_reconnect_block])

      init_model_attributes(properties[:attributes_blacklist],
                            properties[:attributes_whitelist],
                            properties[:inventory_object_attributes],
                            properties[:batch_extra_attributes])

      init_data(properties[:default_values])

      init_storages

      init_changed_records_stats
    end

    def store_unconnected_edges(inventory_object, inventory_object_key, inventory_object_lazy)
      (@unconnected_edges ||= []) <<
        InventoryRefresh::InventoryCollection::UnconnectedEdge.new(
          inventory_object, inventory_object_key, inventory_object_lazy
        )
    end

    # Caches what records were created, for later use, e.g. post provision behavior
    #
    # @param records [Array<ApplicationRecord, Hash>] list of stored records
    def store_created_records(records)
      @created_records.concat(records_identities(records))
    end

    # Caches what records were updated, for later use, e.g. post provision behavior
    #
    # @param records [Array<ApplicationRecord, Hash>] list of stored records
    def store_updated_records(records)
      @updated_records.concat(records_identities(records))
    end

    # Caches what records were deleted/soft-deleted, for later use, e.g. post provision behavior
    #
    # @param records [Array<ApplicationRecord, Hash>] list of stored records
    def store_deleted_records(records)
      @deleted_records.concat(records_identities(records))
    end

    # @return [Array<Symbol>] all columns that are part of the best fit unique index
    def unique_index_columns
      return @unique_index_columns if @unique_index_columns

      @unique_index_columns = unique_index_for(unique_index_keys).columns.map(&:to_sym)
    end

    def unique_index_keys
      @unique_index_keys ||= manager_ref_to_cols.map(&:to_sym)
    end

    # @return [Array<ActiveRecord::ConnectionAdapters::IndexDefinition>] array of all unique indexes known to model
    def unique_indexes
      @unique_indexes_cache if @unique_indexes_cache

      @unique_indexes_cache = model_class.connection.indexes(model_class.table_name).select(&:unique)

      if @unique_indexes_cache.blank?
        raise "#{self} and its table #{model_class.table_name} must have a unique index defined, to"\
                " be able to use saver_strategy :concurrent_safe_batch."
      end

      @unique_indexes_cache
    end

    # Finds an index that fits the list of columns (keys) the best
    #
    # @param keys [Array<Symbol>]
    # @raise [Exception] if the unique index for the columns was not found
    # @return [ActiveRecord::ConnectionAdapters::IndexDefinition] unique index fitting the keys
    def unique_index_for(keys)
      @unique_index_for_keys_cache ||= {}
      @unique_index_for_keys_cache[keys] if @unique_index_for_keys_cache[keys]

      # Take the uniq key having the least number of columns
      @unique_index_for_keys_cache[keys] = uniq_keys_candidates(keys).min_by { |x| x.columns.count }
    end

    # Find candidates for unique key. Candidate must cover all columns we are passing as keys.
    #
    # @param keys [Array<Symbol>]
    # @raise [Exception] if the unique index for the columns was not found
    # @return [Array<ActiveRecord::ConnectionAdapters::IndexDefinition>] Array of unique indexes fitting the keys
    def uniq_keys_candidates(keys)
      # Find all uniq indexes that that are covering our keys
      uniq_key_candidates = unique_indexes.each_with_object([]) { |i, obj| obj << i if (keys - i.columns.map(&:to_sym)).empty? }

      if unique_indexes.blank? || uniq_key_candidates.blank?
        raise "#{self} and its table #{model_class.table_name} must have a unique index defined "\
                "covering columns #{keys} to be able to use saver_strategy :concurrent_safe_batch."
      end

      uniq_key_candidates
    end

    def resource_version_column
      :resource_version
    end

    def internal_columns
      return @internal_columns if @internal_columns

      @internal_columns = [] + internal_timestamp_columns
      @internal_columns << :type if supports_sti?
      @internal_columns += [resource_version_column,
                            :resource_timestamps_max,
                            :resource_timestamps,
                            :resource_timestamp,
                            :resource_counters_max,
                            :resource_counters,
                            :resource_counter].collect do |col|
        col if supports_column?(col)
      end.compact
    end

    def internal_timestamp_columns
      return @internal_timestamp_columns if @internal_timestamp_columns

      @internal_timestamp_columns = %i(created_at created_on updated_at updated_on).collect do |timestamp_col|
        timestamp_col if supports_column?(timestamp_col)
      end.compact
    end

    # @return [Array] Array of column names that have not null constraint
    def not_null_columns
      @not_null_constraint_columns ||= model_class.columns.reject(&:null).map { |x| x.name.to_sym } - [model_class.primary_key.to_sym]
    end

    def base_columns
      @base_columns ||= (unique_index_columns + internal_columns + not_null_columns).uniq
    end

    # @param value [Object] Object we want to test
    # @return [Boolean] true is value is kind of InventoryRefresh::InventoryObject
    def inventory_object?(value)
      value.kind_of?(::InventoryRefresh::InventoryObject)
    end

    # @param value [Object] Object we want to test
    # @return [Boolean] true is value is kind of InventoryRefresh::InventoryObjectLazy
    def inventory_object_lazy?(value)
      value.kind_of?(::InventoryRefresh::InventoryObjectLazy)
    end

    # Builds string uuid from passed Object and keys
    #
    # @param keys [Array<Symbol>] Indexes into the Hash data
    # @param record [ApplicationRecord] ActiveRecord record
    # @return [String] Concatenated values on keys from data
    def object_index_with_keys(keys, record)
      # TODO(lsmola) remove, last usage is in k8s reconnect logic
      build_stringified_reference_for_record(record, keys)
    end

    # Convert manager_ref list of attributes to list of DB columns
    #
    # @return [Array<String>] true is processing of this InventoryCollection will be in targeted mode
    def manager_ref_to_cols
      # TODO(lsmola) this should contain the polymorphic _type, otherwise the IC with polymorphic unique key will get
      # conflicts
      manager_ref.map do |ref|
        association_to_foreign_key_mapping[ref] || ref
      end
    end

    # List attributes causing a dependency and filters them by attributes_blacklist and attributes_whitelist
    #
    # @return [Hash{Symbol => Set}] attributes causing a dependency and filtered by blacklist and whitelist
    def filtered_dependency_attributes
      filtered_attributes = dependency_attributes

      if attributes_blacklist.present?
        filtered_attributes = filtered_attributes.reject { |key, _value| attributes_blacklist.include?(key) }
      end

      if attributes_whitelist.present?
        filtered_attributes = filtered_attributes.select { |key, _value| attributes_whitelist.include?(key) }
      end

      filtered_attributes
    end

    # Attributes that are needed to be able to save the record, i.e. attributes that are part of the unique index
    # and attributes with presence validation or NOT NULL constraint
    #
    # @return [Array<Symbol>] attributes that are needed for saving of the record
    def fixed_attributes
      if model_class
        presence_validators = model_class.validators.detect { |x| x.kind_of?(ActiveRecord::Validations::PresenceValidator) }
      end
      # Attributes that has to be always on the entity, so attributes making unique index of the record + attributes
      # that have presence validation
      fixed_attributes = manager_ref
      fixed_attributes += presence_validators.attributes if presence_validators.present?
      fixed_attributes
    end

    # Returns fixed dependencies, which are the ones we can't move, because we wouldn't be able to save the data
    #
    # @returns [Set<InventoryRefresh::InventoryCollection>] all unique non saved fixed dependencies
    def fixed_dependencies
      fixed_attrs = fixed_attributes

      filtered_dependency_attributes.each_with_object(Set.new) do |(key, value), fixed_deps|
        fixed_deps.merge(value) if fixed_attrs.include?(key)
      end.reject(&:saved?)
    end

    # @return [Array<InventoryRefresh::InventoryCollection>] all unique non saved dependencies
    def dependencies
      filtered_dependency_attributes.values.map(&:to_a).flatten.uniq.reject(&:saved?)
    end

    # Returns what attributes are causing a dependencies to certain InventoryCollection objects.
    #
    # @param inventory_collections [Array<InventoryRefresh::InventoryCollection>]
    # @return [Array<InventoryRefresh::InventoryCollection>] attributes causing the dependencies to certain
    #         InventoryCollection objects
    def dependency_attributes_for(inventory_collections)
      attributes = Set.new
      inventory_collections.each do |inventory_collection|
        attributes += filtered_dependency_attributes.select { |_key, value| value.include?(inventory_collection) }.keys
      end
      attributes
    end

    # Add passed attributes to blacklist. The manager_ref attributes cannot be blacklisted, otherwise we will not
    # be able to identify the inventory_object. We do not automatically remove attributes causing fixed dependencies,
    # so beware that without them, you won't be able to create the record.
    #
    # @param attributes [Array<Symbol>] Attributes we want to blacklist
    # @return [Array<Symbol>] All blacklisted attributes
    def blacklist_attributes!(attributes)
      self.attributes_blacklist += attributes - (fixed_attributes + internal_attributes)
    end

    # Add passed attributes to whitelist. The manager_ref attributes always needs to be in the white list, otherwise
    # we will not be able to identify theinventory_object. We do not automatically add attributes causing fixed
    # dependencies, so beware that without them, you won't be able to create the record.
    #
    # @param attributes [Array<Symbol>] Attributes we want to whitelist
    # @return [Array<Symbol>] All whitelisted attributes
    def whitelist_attributes!(attributes)
      self.attributes_whitelist += attributes + (fixed_attributes + internal_attributes)
    end

    # @return [InventoryCollection] a shallow copy of InventoryCollection, the copy will share data_storage of the
    #         original collection, otherwise we would be copying a lot of records in memory.
    def clone
      cloned = self.class.new(:model_class           => model_class,
                              :manager_ref           => manager_ref,
                              :association           => association,
                              :parent                => parent,
                              :arel                  => arel,
                              :strategy              => strategy,
                              :saver_strategy        => saver_strategy,
                              :custom_save_block     => custom_save_block,
                              # We want cloned IC to be update only, since this is used for cycle resolution
                              :update_only           => true,
                              # Dependency attributes need to be a hard copy, since those will differ for each
                              # InventoryCollection
                              :dependency_attributes => dependency_attributes.clone)

      cloned.data_storage = data_storage
      cloned
    end

    # @return [String] Base class name of the model_class of this InventoryCollection
    def base_class_name
      return "" unless model_class

      @base_class_name ||= model_class.base_class.name
    end

    # @return [String] a concise form of the inventoryCollection for easy logging
    def to_s
      whitelist = ", whitelist: [#{attributes_whitelist.to_a.join(", ")}]" if attributes_whitelist.present?
      blacklist = ", blacklist: [#{attributes_blacklist.to_a.join(", ")}]" if attributes_blacklist.present?

      strategy_name = ", strategy: #{strategy}" if strategy

      name = model_class || association

      "InventoryCollection:<#{name}>#{whitelist}#{blacklist}#{strategy_name}"
    end

    # @return [String] a concise form of the InventoryCollection for easy logging
    def inspect
      to_s
    end

    # @return [Integer] default batch size for talking to the DB
    def batch_size
      # TODO(lsmola) mode to the settings
      1000
    end

    # @return [Integer] default batch size for talking to the DB if not using ApplicationRecord objects
    def batch_size_pure_sql
      # TODO(lsmola) mode to the settings
      10_000
    end

    # Builds a multiselection conditions like (table1.a = a1 AND table2.b = b1) OR (table1.a = a2 AND table2.b = b2)
    #
    # @param hashes [Array<Hash>] data we want to use for the query
    # @param keys [Array<Symbol>] keys of attributes involved
    # @return [String] A condition usable in .where of an ActiveRecord relation
    def build_multi_selection_condition(hashes, keys = unique_index_keys)
      arel_table = model_class.arel_table
      # We do pure SQL OR, since Arel is nesting every .or into another parentheses, otherwise this would be just
      # inject(:or) instead of to_sql with .join(" OR ")
      hashes.map { |hash| "(#{keys.map { |key| arel_table[key].eq(hash[key]) }.inject(:and).to_sql})" }.join(" OR ")
    end

    # @return [ActiveRecord::Relation] A relation that can fetch all data of this InventoryCollection from the DB
    def db_collection_for_comparison
      if targeted?
        targeted_iterator
      else
        full_collection_for_comparison
      end
    end

    # Builds a multiselection conditions like (table1.a = a1 AND table2.b = b1) OR (table1.a = a2 AND table2.b = b2)
    # for passed references
    #
    # @param references [Hash{String => InventoryRefresh::InventoryCollection::Reference}] passed references
    # @return [String] A condition usable in .where of an ActiveRecord relation
    def targeted_selection_for(references)
      build_multi_selection_condition(references.map { |x| x.second })
    end

    # Returns iterator for the passed references and a query
    #
    # @param query [ActiveRecord::Relation] relation that can fetch all data of this InventoryCollection from the DB
    # @return [InventoryRefresh::ApplicationRecordIterator] Iterator for the references and query
    def targeted_iterator(query = nil)
      InventoryRefresh::ApplicationRecordIterator.new(
        :inventory_collection => self,
        :query                => query
      )
    end

    # Builds an ActiveRecord::Relation that can fetch all the references from the DB
    #
    # @param references [Hash{String => InventoryRefresh::InventoryCollection::Reference}] passed references
    # @return [ActiveRecord::Relation] relation that can fetch all the references from the DB
    def db_collection_for_comparison_for(references)
      full_collection_for_comparison.where(targeted_selection_for(references))
    end

    # @return [ActiveRecord::Relation] relation that can fetch all the references from the DB
    def full_collection_for_comparison
      return arel unless arel.nil?
      rel = parent.send(association)
      rel = rel.active if rel && supports_column?(:archived_at) && retention_strategy == :archive
      rel
    end

    # Creates InventoryRefresh::InventoryObject object from passed hash data
    #
    # @param hash [Hash] Object data
    # @return [InventoryRefresh::InventoryObject] Instantiated InventoryRefresh::InventoryObject
    def new_inventory_object(hash)
      manager_ref.each do |x|
        # TODO(lsmola) with some effort, we can do this, but it's complex
        raise "A lazy_find with a :key can't be a part of the manager_uuid" if inventory_object_lazy?(hash[x]) && hash[x].key
      end

      inventory_object_class.new(self, hash)
    end

    attr_writer :attributes_blacklist, :attributes_whitelist

    private

    # Creates dynamically a subclass of InventoryRefresh::InventoryObject, that will be used per InventoryCollection
    # object. This approach is needed because we want different InventoryObject's getters&setters for each
    # InventoryCollection.
    #
    # @return [InventoryRefresh::InventoryObject] new isolated subclass of InventoryRefresh::InventoryObject
    def inventory_object_class
      @inventory_object_class ||= begin
        klass = Class.new(::InventoryRefresh::InventoryObject)
        klass.add_attributes(inventory_object_attributes) if inventory_object_attributes
        klass
      end
    end

    # Returns array of records identities
    #
    # @param records [Array<ApplicationRecord>, Array[Hash]] list of stored records
    # @return [Array<Hash>] array of records identities
    def records_identities(records)
      records = [records] unless records.respond_to?(:map)
      records.map { |record| record_identity(record) }
    end

    # Returns a hash with a simple record identity
    #
    # @param record [ApplicationRecord, Hash] list of stored records
    # @return [Hash{Symbol => Bigint}] record identity
    def record_identity(record)
      identity = record.try(:[], :id) || record.try(:[], "id") || record.try(:id)
      raise "Cannot obtain identity of the #{record}" if identity.blank?
      {
        :id => identity
      }
    end

    # TODO: Not used!
    # @return [Array<Symbol>] all association attributes and foreign keys of the model class
    def association_attributes
      model_class.reflect_on_all_associations.map { |x| [x.name, x.foreign_key] }.flatten.compact.map(&:to_sym)
    end
  end
end
