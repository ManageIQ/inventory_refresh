require_relative "../helpers"

module InventoryRefresh
  class InventoryCollection
    module Helpers
      module QuestionsHelper
        # @return [Boolean] true means we want to call .changed? on every ActiveRecord object before saving it
        def check_changed?
          check_changed
        end

        # @return [Boolean] true means we want to use ActiveRecord object for writing attributes and we want to perform
        #         casting on all columns
        def use_ar_object?
          use_ar_object
        end

        # @return [Boolean] true means the data is not complete, leading to only creating and updating data
        def complete?
          complete
        end

        # @return [Boolean] true means we want to only update data
        def update_only?
          update_only
        end

        # @return [Boolean] true means we will delete/soft-delete data
        def delete_allowed?
          complete? && !update_only?
        end

        # @return [Boolean] true means we will delete/soft-delete data
        def create_allowed?
          !update_only?
        end

        # @return [Boolean] true means that only create of new data is allowed
        def create_only?
          create_only
        end

        # @return [Boolean] true if the whole InventoryCollection object has all data persisted
        def saved?
          saved
        end

        # @return [Boolean] true if all dependencies have all data persisted
        def saveable?
          dependencies.all?(&:saved?)
        end

        # @return [Boolean] true if we are using a saver strategy that allows saving in parallel processes
        def parallel_safe?
          @parallel_safe_cache ||= %i(concurrent_safe concurrent_safe_batch).include?(saver_strategy)
        end

        # @return [Boolean] true if the model_class supports STI
        def supports_sti?
          @supports_sti_cache = model_class.column_names.include?("type") if @supports_sti_cache.nil?
          @supports_sti_cache
        end

        # @param column_name [Symbol, String]
        # @return [Boolean] true if the model_class supports given column
        def supports_column?(column_name)
          @supported_cols_cache ||= {}
          return @supported_cols_cache[column_name.to_sym] unless @supported_cols_cache[column_name.to_sym].nil?

          include_col = model_class.column_names.include?(column_name.to_s)
          if %w(created_on created_at updated_on updated_at).include?(column_name.to_s)
            include_col &&= ActiveRecord::Base.record_timestamps
          end

          @supported_cols_cache[column_name.to_sym] = include_col
        end

        # @return [Boolean] true if no more data will be added to this InventoryCollection object, that usually happens
        #         after the parsing step is finished
        def data_collection_finalized?
          data_collection_finalized
        end

        # @return [Boolean] true is processing of this InventoryCollection will be in targeted mode
        def targeted?
          targeted
        end

        # True if processing of this InventoryCollection object would lead to no operations. Then we use this marker to
        # stop processing of the InventoryCollector object very soon, to avoid a lot of unnecessary Db queries, etc.
        #
        # @return [Boolean] true if processing of this InventoryCollection object would lead to no operations.
        def noop?
          # If this InventoryCollection doesn't do anything. it can easily happen for targeted/batched strategies.
          saving_noop? && delete_complement_noop?
        end

        # @return [Boolean] true if processing InventoryCollection will not lead to any created/updated/deleted record
        def saving_noop?
          saving_targeted_collection_noop? || saving_full_collection_noop?
        end

        # @return true if processing InventoryCollection will not lead to deleting the complement of passed ids
        def delete_complement_noop?
          all_manager_uuids.nil?
        end

        private

        # @return true if it's a noop parent targeted InventoryCollection
        def saving_targeted_collection_noop?
          targeted_noop_condition && parent_inventory_collections.blank?
        end

        # @return true if it's a noop full InventoryCollection refresh
        def saving_full_collection_noop?
          !targeted? && data.blank? && !delete_allowed? && skeletal_primary_index.blank?
        end

        def targeted_noop_condition
          targeted? && data.blank? && custom_save_block.nil? && skeletal_primary_index.blank?
        end
      end
    end
  end
end
