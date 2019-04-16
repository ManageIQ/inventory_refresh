require "inventory_refresh/save_collection/saver/base"
require "inventory_refresh/save_collection/saver/partial_upsert_helper"
require "inventory_refresh/save_collection/saver/retention_helper"
require "active_support/core_ext/module/delegation"

module InventoryRefresh::SaveCollection
  module Saver
    class ConcurrentSafeBatch < InventoryRefresh::SaveCollection::Saver::Base
      private

      # Methods for archiving or deleting non existent records
      include InventoryRefresh::SaveCollection::Saver::PartialUpsertHelper
      include InventoryRefresh::SaveCollection::Saver::RetentionHelper

      delegate :association_to_base_class_mapping,
               :association_to_foreign_key_mapping,
               :association_to_foreign_type_mapping,
               :attribute_references,
               :resource_version_column,
               :to => :inventory_collection

      # Attribute accessor to ApplicationRecord object or Hash
      #
      # @param record [Hash, ApplicationRecord] record or hash
      # @param key [String] key pointing to attribute of the record
      # @return [Object] value of the record on the key
      def record_key(record, key)
        send(record_key_method, record, key)
      end

      # Attribute accessor to ApplicationRecord object
      #
      # @param record [ApplicationRecord] record
      # @param key [String] key pointing to attribute of the record
      # @return [Object] value of the record on the key
      def ar_record_key(record, key)
        record.public_send(key)
      end

      # Attribute accessor to Hash object
      #
      # @param record [Hash] hash
      # @param key [String] key pointing to attribute of the record
      # @return [Object] value of the record on the key
      def pure_sql_record_key(record, key)
        record[select_keys_indexes[key]]
      end

      # Saves the InventoryCollection
      #
      # @param association [Symbol] An existing association on manager
      def save!(association)
        attributes_index        = {}
        inventory_objects_index = {}
        all_attribute_keys      = Set.new + inventory_collection.batch_extra_attributes

        inventory_collection.each do |inventory_object|
          attributes = inventory_object.class.attributes_with_keys(inventory_object.data, inventory_collection, all_attribute_keys, inventory_object)
          index      = build_stringified_reference(attributes, unique_index_keys)

          # Interesting fact: not building attributes_index and using only inventory_objects_index doesn't do much
          # of a difference, since the most objects inside are shared.
          attributes_index[index]        = attributes
          inventory_objects_index[index] = inventory_object
        end

        expand_all_attribute_keys!(all_attribute_keys)

        logger.debug("Processing #{inventory_collection} of size #{inventory_collection.size}...")

        unless inventory_collection.create_only?
          update_or_destroy_records!(association, inventory_objects_index, attributes_index, all_attribute_keys)
        end

        unless inventory_collection.create_only?
          inventory_collection.custom_reconnect_block&.call(inventory_collection, inventory_objects_index, attributes_index)
        end

        # Records that were not found in the DB but sent for saving, we will be creating these in the DB.
        if inventory_collection.create_allowed?
          on_conflict = inventory_collection.parallel_safe? ? :do_update : nil

          inventory_objects_index.each_slice(batch_size_for_persisting) do |batch|
            create_records!(all_attribute_keys, batch, attributes_index, :on_conflict => on_conflict)
          end

          if inventory_collection.parallel_safe?
            create_or_update_partial_records(all_attribute_keys)
          end
        end

        logger.debug("Marking :last_seen_at of #{inventory_collection} of size #{inventory_collection.size}...")

        mark_last_seen_at(attributes_index)

        # Let the GC clean this up
        inventory_objects_index = nil
        attributes_index = nil

        logger.debug("Processing #{inventory_collection}, "\
                     "created=#{inventory_collection.created_records.count}, "\
                     "updated=#{inventory_collection.updated_records.count}, "\
                     "deleted=#{inventory_collection.deleted_records.count}...Complete")
      rescue => e
        logger.error("Error when saving #{inventory_collection} with #{inventory_collection_details}. Message: #{e.message}")
        raise e
      end

      def expand_all_attribute_keys!(all_attribute_keys)
        %i(created_at updated_at created_on updated_on).each do |col|
          all_attribute_keys << col if supports_column?(col)
        end
        all_attribute_keys << :type if supports_sti?
        all_attribute_keys << :archived_at if supports_column?(:archived_at)
      end

      def mark_last_seen_at(attributes_index)
        return unless supports_column?(:last_seen_at) && inventory_collection.parallel_safe?
        return if attributes_index.blank?

        all_attribute_keys = [:last_seen_at]

        last_seen_at = Time.now.utc
        attributes_index.each_value { |v| v[:last_seen_at] = last_seen_at }

        query = build_partial_update_query(all_attribute_keys, attributes_index.values)

        get_connection.execute(query)
      end

      # Batch updates existing records that are in the DB using attributes_index. And delete the ones that were not
      # present in inventory_objects_index.
      #
      # @param records_batch_iterator [ActiveRecord::Relation, InventoryRefresh::ApplicationRecordIterator] iterator or
      #        relation, both responding to :find_in_batches method
      # @param inventory_objects_index [Hash{String => InventoryRefresh::InventoryObject}] Hash of InventoryObject objects
      # @param attributes_index [Hash{String => Hash}] Hash of data hashes with only keys that are column names of the
      #        models's table
      # @param all_attribute_keys [Array<Symbol>] Array of all columns we will be saving into each table row
      def update_or_destroy_records!(records_batch_iterator, inventory_objects_index, attributes_index, all_attribute_keys)
        hashes_for_update   = []
        records_for_destroy = []
        indexed_inventory_objects = {}

        records_batch_iterator.find_in_batches(:batch_size => batch_size, :attributes_index => attributes_index) do |batch|
          update_time = time_now

          batch.each do |record|
            primary_key_value = record_key(record, primary_key)

            next unless assert_distinct_relation(primary_key_value)

            index = db_columns_index(record)

            inventory_object = inventory_objects_index.delete(index)
            hash             = attributes_index[index]

            if inventory_object.nil?
              # Record was found in the DB but not sent for saving, that means it doesn't exist anymore and we should
              # delete it from the DB.
              if inventory_collection.delete_allowed?
                records_for_destroy << record
              end
            else
              # Record was found in the DB and sent for saving, we will be updating the DB.
              inventory_object.id = primary_key_value
              next unless assert_referential_integrity(hash)
              next unless changed?(record, hash, all_attribute_keys)

              if inventory_collection.parallel_safe? &&
                 (supports_remote_data_timestamp?(all_attribute_keys) || supports_remote_data_version?(all_attribute_keys))

                version_attr, max_version_attr = if supports_remote_data_timestamp?(all_attribute_keys)
                                                   [:resource_timestamp, :resource_timestamps_max]
                                                 elsif supports_remote_data_version?(all_attribute_keys)
                                                   [:resource_counter, :resource_counters_max]
                                                 end

                next if skeletonize_or_skip_record(record_key(record, version_attr.to_s),
                                                   hash[version_attr],
                                                   record_key(record, max_version_attr.to_s),
                                                   inventory_object)
              end

              hash_for_update = if inventory_collection.use_ar_object?
                                  record.assign_attributes(hash.except(:id))
                                  values_for_database!(all_attribute_keys,
                                                       record.attributes.symbolize_keys)
                                elsif serializable_keys?
                                  # TODO(lsmola) hash data with current DB data to allow subset of data being sent,
                                  # otherwise we would nullify the not sent attributes. Test e.g. on disks in cloud
                                  values_for_database!(all_attribute_keys,
                                                       hash)
                                else
                                  # TODO(lsmola) hash data with current DB data to allow subset of data being sent,
                                  # otherwise we would nullify the not sent attributes. Test e.g. on disks in cloud
                                  hash
                                end
              assign_attributes_for_update!(hash_for_update, update_time)

              hash_for_update[:id] = primary_key_value
              indexed_inventory_objects[index] = inventory_object
              hashes_for_update << hash_for_update
            end
          end

          # Update in batches
          if hashes_for_update.size >= batch_size_for_persisting
            update_records!(all_attribute_keys, hashes_for_update, indexed_inventory_objects)

            hashes_for_update = []
            indexed_inventory_objects = {}
          end

          # Destroy in batches
          if records_for_destroy.size >= batch_size_for_persisting
            destroy_records!(records_for_destroy)
            records_for_destroy = []
          end
        end

        # Update the last batch
        update_records!(all_attribute_keys, hashes_for_update, indexed_inventory_objects)
        hashes_for_update = [] # Cleanup so GC can release it sooner

        # Destroy the last batch
        destroy_records!(records_for_destroy)
        records_for_destroy = [] # Cleanup so GC can release it sooner
      end

      def changed?(_record, _hash, _all_attribute_keys)
        return true unless inventory_collection.check_changed?

        # TODO(lsmola) this check needs to be disabled now, because it doesn't work with lazy_find having secondary
        # indexes. Examples: we save a pod before we save a project, that means the project lazy_find won't evaluate,
        # because we load it with secondary index and can't do skeletal precreate. Then when the object is being saved
        # again, the lazy_find is evaluated, but the resource version is not changed, so the row is not saved.
        #
        # To keep this quick .changed? check, we might need to extend this, so the resource_version doesn't save until
        # all lazy_links of the row are evaluated.
        #
        # if supports_resource_version?(all_attribute_keys) && supports_column?(resource_version_column)
        #   record_resource_version = record_key(record, resource_version_column.to_s)
        #
        #   return record_resource_version != hash[resource_version_column]
        # end

        true
      end

      def db_columns_index(record, pure_sql: false)
        # Incoming values are in SQL string form.
        # TODO(lsmola) unify this behavior with object_index_with_keys method in InventoryCollection
        # with streaming refresh? Maybe just metrics and events will not be, but those should be upsert only
        unique_index_keys_to_s.map do |attribute|
          value = if pure_sql
                    record[attribute]
                  else
                    record_key(record, attribute)
                  end

          format_value(attribute, value)
        end.join("__")
      end

      def format_value(attribute, value)
        if attribute == "timestamp"
          # TODO: can this be covered by @deserializable_keys?
          type = model_class.type_for_attribute(attribute)
          type.cast(value).utc.iso8601.to_s
        elsif (type = deserializable_keys[attribute.to_sym])
          type.deserialize(value).to_s
        else
          value.to_s
        end
      end

      # Batch updates existing records
      #
      # @param hashes [Array<Hash>] data used for building a batch update sql query
      # @param all_attribute_keys [Array<Symbol>] Array of all columns we will be saving into each table row
      def update_records!(all_attribute_keys, hashes, indexed_inventory_objects)
        return if hashes.blank?

        unless inventory_collection.parallel_safe?
          # We need to update the stored records before we save it, since hashes are modified
          inventory_collection.store_updated_records(hashes)
        end

        query = build_update_query(all_attribute_keys, hashes)
        result = get_connection.execute(query)

        if inventory_collection.parallel_safe?
          # We will check for timestamp clashes of full row update and we will fallback to skeletal update
          inventory_collection.store_updated_records(result)

          skeletonize_ignored_records!(indexed_inventory_objects, result)
        end

        result
      end

      # Batch inserts records using attributes_index data. With on_conflict option using :do_update, this method
      # does atomic upsert.
      #
      # @param all_attribute_keys [Array<Symbol>] Array of all columns we will be saving into each table row
      # @param batch [Array<InventoryRefresh::InventoryObject>] Array of InventoryObject object we will be inserting into
      #        the DB
      # @param attributes_index [Hash{String => Hash}] Hash of data hashes with only keys that are column names of the
      #        models's table
      # @param on_conflict [Symbol, NilClass] defines behavior on conflict with unique index constraint, allowed values
      #        are :do_update, :do_nothing, nil
      def create_records!(all_attribute_keys, batch, attributes_index, on_conflict: nil)
        indexed_inventory_objects = {}
        hashes                    = []
        create_time               = time_now
        batch.each do |index, inventory_object|
          hash = if inventory_collection.use_ar_object?
                   record = inventory_collection.model_class.new(attributes_index[index])
                   values_for_database!(all_attribute_keys,
                                        record.attributes.symbolize_keys)
                 elsif serializable_keys?
                   values_for_database!(all_attribute_keys,
                                        attributes_index[index])
                 else
                   attributes_index[index]
                 end

          assign_attributes_for_create!(hash, create_time)

          next unless assert_referential_integrity(hash)

          hashes << hash
          # Index on Unique Columns values, so we can easily fill in the :id later
          indexed_inventory_objects[unique_index_columns.map { |x| hash[x] }] = inventory_object
        end

        return if hashes.blank?

        result = get_connection.execute(
          build_insert_query(all_attribute_keys, hashes, :on_conflict => on_conflict, :mode => :full)
        )

        if inventory_collection.parallel_safe?
          # We've done upsert, so records were either created or updated. We can recognize that by checking if
          # created and updated timestamps are the same
          created_attr = "created_on" if inventory_collection.supports_column?(:created_on)
          created_attr ||= "created_at" if inventory_collection.supports_column?(:created_at)
          updated_attr = "updated_on" if inventory_collection.supports_column?(:updated_on)
          updated_attr ||= "updated_at" if inventory_collection.supports_column?(:updated_at)

          if created_attr && updated_attr
            created, updated = result.to_a.partition { |x| x[created_attr] == x[updated_attr] }
            inventory_collection.store_created_records(created)
            inventory_collection.store_updated_records(updated)
          else
            # The record doesn't have both created and updated attrs, so we'll take all as created
            inventory_collection.store_created_records(result)
          end
        else
          # We've done just insert, so all records were created
          inventory_collection.store_created_records(result)
        end

        if inventory_collection.dependees.present?
          # We need to get primary keys of the created objects, but only if there are dependees that would use them
          map_ids_to_inventory_objects(indexed_inventory_objects,
                                       all_attribute_keys,
                                       hashes,
                                       result,
                                       :on_conflict => on_conflict)
        end

        if inventory_collection.parallel_safe?
          skeletonize_ignored_records!(indexed_inventory_objects, result, :all_unique_columns => true)
        end
      end

      # Stores primary_key values of created records into associated InventoryObject objects.
      #
      # @param indexed_inventory_objects [Hash{String => InventoryRefresh::InventoryObject}] inventory objects indexed
      #        by stringified value made from db_columns
      # @param all_attribute_keys [Array<Symbol>] Array of all columns we will be saving into each table row
      # @param hashes [Array<Hashes>] Array of hashes that were used for inserting of the data
      # @param result [Array<Hashes>] Array of hashes that are a result of the batch insert query, each result
      #        contains a primary key_value plus all columns that are a part of the unique index
      # @param on_conflict [Symbol, NilClass] defines behavior on conflict with unique index constraint, allowed values
      #        are :do_update, :do_nothing, nil
      def map_ids_to_inventory_objects(indexed_inventory_objects, all_attribute_keys, hashes, result, on_conflict:)
        if on_conflict == :do_nothing
          # TODO(lsmola) is the comment below still accurate? We will update some partial rows, the actual skeletal
          # precreate will still do nothing.
          # For ON CONFLICT DO NOTHING, we need to always fetch the records plus the attribute_references. This path
          # applies only for skeletal precreate.
          inventory_collection.model_class.where(
            build_multi_selection_query(hashes)
          ).select(unique_index_columns + [:id] + attribute_references.to_a).each do |record|
            key              = unique_index_columns.map { |x| record.public_send(x) }
            inventory_object = indexed_inventory_objects[key]

            # Load also attribute_references, so lazy_find with :key pointing to skeletal reference works
            attributes = record.attributes.symbolize_keys
            attribute_references.each do |ref|
              inventory_object[ref] = attributes[ref]

              next unless (foreign_key = association_to_foreign_key_mapping[ref])
              base_class_name       = attributes[association_to_foreign_type_mapping[ref].try(:to_sym)] || association_to_base_class_mapping[ref]
              id                    = attributes[foreign_key.to_sym]
              inventory_object[ref] = InventoryRefresh::ApplicationRecordReference.new(base_class_name, id)
            end

            inventory_object.id = record.id if inventory_object
          end
        elsif !supports_remote_data_timestamp?(all_attribute_keys) || result.count == batch_size_for_persisting
          # We can use the insert query result to fetch all primary_key values, which makes this the most effective
          # path.
          result.each do |inserted_record|
            key = unique_index_columns.map do |x|
              value = inserted_record[x.to_s]
              type = deserializable_keys[x]
              type ? type.deserialize(value) : value
            end
            inventory_object    = indexed_inventory_objects[key]
            inventory_object.id = inserted_record[primary_key] if inventory_object
          end
        else
          # The remote_data_timestamp is adding a WHERE condition to ON CONFLICT UPDATE. As a result, the RETURNING
          # clause is not guaranteed to return all ids of the inserted/updated records in the result. In that case
          # we test if the number of results matches the expected batch size. Then if the counts do not match, the only
          # safe option is to query all the data from the DB, using the unique_indexes. The batch size will also not match
          # for every remainders(a last batch in a stream of batches)
          inventory_collection.model_class.where(
            build_multi_selection_query(hashes)
          ).select(unique_index_columns + [:id]).each do |inserted_record|
            key                 = unique_index_columns.map { |x| inserted_record.public_send(x) }
            inventory_object    = indexed_inventory_objects[key]
            inventory_object.id = inserted_record.id if inventory_object
          end
        end
      end
    end
  end
end
