module InventoryRefresh::SaveCollection
  module Saver
    module PartialUpsertHelper
      private

      # Taking result from update or upsert of the row. The records that were not saved will be turned into skeletal
      # records and we will save them attribute by attribute.
      #
      # @param hash [Hash{String => InventoryObject}>] Hash with indexed data we want to save
      # @param result [Array<Hash>] Result from the DB containing the data that were actually saved
      # @param all_unique_columns [Boolean] True if index is consisted from all columns of the unique index. False if
      #        index is just made from manager_ref turned in DB column names.
      def skeletonize_ignored_records!(hash, result, all_unique_columns: false)
        updated = if all_unique_columns
                    result.map { |x| unique_index_columns_to_s.map { |key| x[key] } }
                  else
                    result.map { |x| db_columns_index(x, :pure_sql => true) }
                  end

        updated.each { |x| hash.delete(x) }

        # Now lets skeletonize all inventory_objects that were not saved by update or upsert. Old rows that can't be
        # saved are not being sent here. We have only rows that are new, but become old as we send the query (so other
        # parallel process saved the data in the meantime). Or if some attributes are newer than the whole row
        # being sent.
        hash.each_key do |db_index|
          inventory_collection.skeletal_primary_index.skeletonize_primary_index(hash[db_index].manager_uuid)
        end
      end

      # Saves partial records using upsert, taking records from skeletal_primary_index. This is used both for
      # skeletal precreate as well as for saving partial rows.
      #
      # @param all_attribute_keys [Set] Superset of all keys of all records being saved
      def create_or_update_partial_records(all_attribute_keys)
        skeletal_inventory_objects_index, skeletal_attributes_index = load_partial_attributes(all_attribute_keys)

        indexed_inventory_objects, hashes = process_partial_data(skeletal_inventory_objects_index,
                                                                 skeletal_attributes_index,
                                                                 all_attribute_keys)
        return if hashes.blank?

        processed_record_refs = skeletal_precreate!(hashes, all_attribute_keys)
        hashes_for_update = hashes_for_update(hashes, processed_record_refs)
        partial_updates!(hashes_for_update, all_attribute_keys)

        if inventory_collection.dependees.present?
          # We need to get primary keys of the created objects, but only if there are dependees that would use them
          map_ids_to_inventory_objects(indexed_inventory_objects,
                                       all_attribute_keys,
                                       hashes,
                                       nil,
                                       :on_conflict => :do_nothing)
        end
      end

      def load_partial_attributes(all_attribute_keys)
        skeletal_attributes_index        = {}
        skeletal_inventory_objects_index = {}

        inventory_collection.skeletal_primary_index.each_value do |inventory_object|
          attributes = inventory_object.class.attributes_with_keys(inventory_object.data, inventory_collection, all_attribute_keys, inventory_object)
          index      = build_stringified_reference(attributes, unique_index_keys)

          skeletal_attributes_index[index]        = attributes
          skeletal_inventory_objects_index[index] = inventory_object
        end

        if supports_remote_data_timestamp?(all_attribute_keys)
          all_attribute_keys << :resource_timestamps
          all_attribute_keys << :resource_timestamps_max
        elsif supports_remote_data_version?(all_attribute_keys)
          all_attribute_keys << :resource_counters
          all_attribute_keys << :resource_counters_max
        end

        # We cannot set the resource_version doing partial update
        all_attribute_keys.delete(resource_version_column)

        return skeletal_inventory_objects_index, skeletal_attributes_index
      end

      def hashes_for_update(hashes, processed_record_refs)
        indexed_hashes = hashes.each_with_object({}) { |hash, obj| obj[unique_index_columns.map { |x| hash[x] }] = hash }
        indexed_hashes.except!(*processed_record_refs)
        hashes_for_update = indexed_hashes.values

        # We need only skeletal records with timestamp. We can't save the ones without timestamp, because e.g. skeletal
        # precreate would be updating records with default values, that are not correct.
        hashes_for_update.select { |x| x[:resource_timestamps_max] || x[:resource_counters_max] }
      end

      def skeletal_precreate!(hashes, all_attribute_keys)
        processed_record_refs = []
        # First, lets try to create all partial records
        hashes.each_slice(batch_size_for_persisting) do |batch|
          result = create_partial!(all_attribute_keys,
                                   batch,
                                   :on_conflict => :do_nothing)
          inventory_collection.store_created_records(result)
          # Store refs of created records, so we can ignore them for update
          result.each { |hash| processed_record_refs << unique_index_columns.map { |x| hash[x.to_s] } }
        end

        processed_record_refs
      end

      def partial_updates!(hashes, all_attribute_keys)
        results = {}
        (all_attribute_keys - inventory_collection.base_columns).each do |column_name|
          filtered = hashes.select { |x| x.key?(column_name) }

          filtered.each_slice(batch_size_for_persisting) do |batch|
            partial_update!(batch, all_attribute_keys, column_name, results)
          end
        end

        inventory_collection.store_updated_records(results.values)
      end

      def partial_update!(batch, all_attribute_keys, column_name, results)
        fill_comparables_max!(batch, all_attribute_keys, column_name)
        result = create_partial!((inventory_collection.base_columns + [column_name]).to_set & all_attribute_keys,
                                 batch,
                                 :on_conflict => :do_update,
                                 :column_name => column_name)
        result.each do |res|
          results[res["id"]] = res
        end
      end

      def fill_comparables_max!(batch, all_attribute_keys, column_name)
        comparables_max_name = comparable_max_column_name(all_attribute_keys)

        # We need to set correct timestamps_max for this particular attribute, based on what is in timestamps
        batch.each do |x|
          next unless x[:__non_serialized_versions][column_name]
          x[comparables_max_name] = x[:__non_serialized_versions][column_name]
        end
      end

      def comparable_max_column_name(all_attribute_keys)
        if supports_remote_data_timestamp?(all_attribute_keys)
          :resource_timestamps_max
        elsif supports_remote_data_version?(all_attribute_keys)
          :resource_counters_max
        end
      end

      def process_partial_data(skeletal_inventory_objects_index, skeletal_attributes_index, all_attribute_keys)
        indexed_inventory_objects = {}
        hashes                    = []
        create_time               = time_now

        skeletal_inventory_objects_index.each do |index, inventory_object|
          hash = prepare_partial_hash(skeletal_attributes_index.delete(index), all_attribute_keys, create_time)
          next unless assert_referential_integrity(hash)

          hashes << hash
          # Index on Unique Columns values, so we can easily fill in the :id later
          indexed_inventory_objects[unique_index_columns.map { |x| hash[x] }] = inventory_object
        end

        return indexed_inventory_objects, hashes
      end

      def prepare_partial_hash(hash, all_attribute_keys, create_time)
        # Partial create or update must never set a timestamp for the whole row
        timestamps = if supports_remote_data_timestamp?(all_attribute_keys) && supports_column?(:resource_timestamps_max)
                       assign_partial_row_version_attributes!(:resource_timestamp,
                                                              :resource_timestamps,
                                                              hash,
                                                              all_attribute_keys)
                     elsif supports_remote_data_version?(all_attribute_keys) && supports_column?(:resource_counters_max)
                       assign_partial_row_version_attributes!(:resource_counter,
                                                              :resource_counters,
                                                              hash,
                                                              all_attribute_keys)
                     end
        # Transform hash to DB format
        hash = transform_to_hash!(all_attribute_keys, hash)

        assign_attributes_for_create!(hash, create_time)

        hash[:__non_serialized_versions] = timestamps # store non serialized timestamps for the partial updates
        hash
      end

      # Batch upserts 1 data column of the row, plus the internal columns
      #
      # @param all_attribute_keys [Array<Symbol>] Array of all columns we will be saving into each table row
      # @param hashes [Array<InventoryRefresh::InventoryObject>] Array of InventoryObject objects we will be inserting
      #        into the DB
      # @param on_conflict [Symbol, NilClass] defines behavior on conflict with unique index constraint, allowed values
      #        are :do_update, :do_nothing, nil
      # @param column_name [Symbol] Name of the data column we will be upserting
      def create_partial!(all_attribute_keys, hashes, on_conflict: nil, column_name: nil)
        get_connection.execute(
          build_insert_query(all_attribute_keys, hashes, :on_conflict => on_conflict, :mode => :partial, :column_name => column_name)
        )
      end

      def skeletonize_or_skip_record(record_version, hash_version, record_versions_max, inventory_object)
        # The hash version is string, the record_version and record_versions_max will be time object, ruby will
        # automatically cast it, so we can compare them
        if record_version.kind_of?(String)
          record_version = Time.use_zone('UTC') { Time.zone.parse(record_version) }.to_s
          record_versions_max = Time.use_zone('UTC') { Time.zone.parse(record_versions_max) }.to_s if record_versions_max
        elsif record_version.kind_of?(Time)
          record_version = record_version.to_s
          record_versions_max = record_versions_max.to_s if record_versions_max
        end

        hash_version = hash_version.to_s if hash_version.kind_of?(Time)

        # Skip updating this record, because it is old
        return true if record_version && hash_version && record_version >= hash_version

        # Some column has bigger version than the whole row, we need to store the row partially
        if record_versions_max && hash_version && record_versions_max > hash_version
          inventory_collection.skeletal_primary_index.skeletonize_primary_index(inventory_object.manager_uuid)
          return true
        end

        false
      end

      def assign_partial_row_version_attributes!(full_row_version_attr, partial_row_version_attr, hash, all_attribute_keys)
        hash[comparable_max_column_name(all_attribute_keys)] = hash.delete(full_row_version_attr)

        return if hash[partial_row_version_attr].blank?

        # Lets clean to only what we save, since when we build the skeletal object, we can set more
        hash[partial_row_version_attr] = hash[partial_row_version_attr].slice(*all_attribute_keys)
      end
    end
  end
end
