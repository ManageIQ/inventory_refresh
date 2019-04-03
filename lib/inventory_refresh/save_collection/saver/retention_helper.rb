module InventoryRefresh::SaveCollection
  module Saver
    module RetentionHelper
      private

      # Applies strategy based on :retention_strategy parameter, or fallbacks to legacy_destroy_records.
      #
      # @param records [Array<ApplicationRecord, Hash, Array>] Records we want to delete or archive
      def destroy_records!(records)
        # TODO(lsmola) the output of this can still grow in a memory a lot, if we would delete a huge chunk of
        # records. Will we just stream it out? Or maybe give a max amount of deleted records here?

        return false unless inventory_collection.delete_allowed?
        return if records.blank?

        ids = ids_array(records)
        inventory_collection.store_deleted_records(ids)
        send("#{inventory_collection.retention_strategy}_all_records!", ids)
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
        inventory_collection.model_class.where(:id => records.map { |x| x[:id] }).update_all(:archived_at => Time.now.utc)
      end

      # Destroys all records
      #
      # @param records [Array<Hash>] Records we want to delete.
      def destroy_all_records!(records)
        inventory_collection.model_class.where(:id => records.map { |x| x[:id] }).delete_all
      end
    end
  end
end
