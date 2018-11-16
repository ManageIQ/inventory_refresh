module InventoryRefresh::SaveCollection
  module Saver
    module RetentionHelper
      private

      # Deletes a complement of referenced data
      def delete_complement
        return unless inventory_collection.delete_allowed?

        all_manager_uuids_size = inventory_collection.all_manager_uuids.size

        logger.debug("Processing :delete_complement of #{inventory_collection} of size "\
                     "#{all_manager_uuids_size}...")

        query = complement_of!(inventory_collection.all_manager_uuids,
                               inventory_collection.all_manager_uuids_scope,
                               inventory_collection.all_manager_uuids_timestamp)

        ids_of_non_active_entities = ActiveRecord::Base.connection.execute(query.to_sql).to_a
        ids_of_non_active_entities.each_slice(10_000) do |batch|
          destroy_records!(batch)
        end

        logger.debug("Processing :delete_complement of #{inventory_collection} of size "\
                     "#{all_manager_uuids_size}, deleted=#{inventory_collection.deleted_records.size}...Complete")
      end

      # Applies strategy based on :retention_strategy parameter, or fallbacks to legacy_destroy_records.
      #
      # @param records [Array<ApplicationRecord, Hash, Array>] Records we want to delete or archive
      def destroy_records!(records)
        return false unless inventory_collection.delete_allowed?
        return if records.blank?

        if inventory_collection.retention_strategy
          ids = ids_array(records)
          inventory_collection.store_deleted_records(ids)
          send("#{inventory_collection.retention_strategy}_all_records!", ids)
        else
          legacy_destroy_records!(records)
        end
      end

      # Convert records to list of ids in format [{:id => X}, {:id => Y}...]
      #
      # @param records [Array<ApplicationRecord, Hash, Array>] Records we want to delete or archive
      # @return [Array<Hash>] Primary keys in standardized format
      def ids_array(records)
        if records.first.kind_of?(Hash)
          records.map { |x| {:id => x[primary_key]} }
        elsif records.first.kind_of?(Array)
          records.map { |x| {:id => x[select_keys_indexes[primary_key]]} }
        else
          records.map { |x| {:id => x.public_send(primary_key)} }
        end
      end

      # Archives all records
      #
      # @param records [Array<Hash>] Records we want to archive.
      def archive_all_records!(records)
        inventory_collection.model_class.where(:id => records.map { |x| x[:id] }).update_all(:archived_on => Time.now.utc)
      end

      # Destroys all records
      #
      # @param records [Array<Hash>] Records we want to delete.
      def destroy_all_records!(records)
        inventory_collection.model_class.where(:id => records.map { |x| x[:id] }).delete_all
      end

      # Deletes or sof-deletes records. If the model_class supports a custom class delete method, we will use it for
      # batch soft-delete. This is the legacy method doing either ineffective deletion/archiving or requiring a method
      # on a class.
      #
      # @param records [Array<ApplicationRecord, Hash>] Records we want to delete. If we have only hashes, we need to
      #        to fetch ApplicationRecord objects from the DB
      def legacy_destroy_records!(records)
        # Is the delete_method rails standard deleting method?
        rails_delete = %i(destroy delete).include?(inventory_collection.delete_method)
        if !rails_delete && inventory_collection.model_class.respond_to?(inventory_collection.delete_method)
          # We have custom delete method defined on a class, that means it supports batch destroy
          inventory_collection.store_deleted_records(records.map { |x| {:id => record_key(x, primary_key)} })
          inventory_collection.model_class.public_send(inventory_collection.delete_method, records.map { |x| record_key(x, primary_key) })
        else
          legacy_ineffective_destroy_records(records)
        end
      end

      # Very ineffective way of deleting records, but is needed if we want to invoke hooks.
      #
      # @param records [Array<ApplicationRecord, Hash>] Records we want to delete. If we have only hashes, we need to
      #        to fetch ApplicationRecord objects from the DB
      def legacy_ineffective_destroy_records(records)
        # We have either standard :destroy and :delete rails method, or custom instance level delete method
        # Note: The standard :destroy and :delete rails method can't be batched because of the hooks and cascade destroy
        ActiveRecord::Base.transaction do
          if pure_sql_records_fetching
            # For pure SQL fetching, we need to get the AR objects again, so we can call destroy
            inventory_collection.model_class.where(:id => records.map { |x| record_key(x, primary_key) }).find_each do |record|
              delete_record!(record)
            end
          else
            records.each do |record|
              delete_record!(record)
            end
          end
        end
      end
    end
  end
end
