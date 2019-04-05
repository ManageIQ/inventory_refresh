module InventoryRefresh
  class ApplicationRecordIterator
    attr_reader :inventory_collection, :manager_uuids_set, :iterator, :query

    # An iterator that can fetch batches of the AR objects based on a set of attribute_indexes
    #
    # @param inventory_collection [InventoryRefresh::InventoryCollection] Inventory collection owning the iterator
    def initialize(inventory_collection: nil)
      @inventory_collection = inventory_collection
    end

    # Iterator that mimics find_in_batches of ActiveRecord::Relation. This iterator serves for making more optimized query
    # since e.g. having 1500 ids if objects we want to return. Doing relation.where(:id => 1500ids).find_each would
    # always search for all 1500 ids, then return on limit 1000.
    #
    # With this iterator we build queries using only batch of ids, so find_each will cause relation.where(:id => 1000ids)
    # and relation.where(:id => 500ids)
    #
    # @param batch_size [Integer] A batch size we want to fetch from DB
    # @param attributes_index [Hash{String => Hash}] Indexed hash with data we will be saving
    # @yield Code processing the batches
    def find_in_batches(batch_size: 1000, attributes_index: {})
      attributes_index.each_slice(batch_size) do |batch|
        yield(inventory_collection.db_collection_for_comparison_for(batch))
      end
    end

    # Iterator that mimics find_each of ActiveRecord::Relation using find_in_batches (see #find_in_batches)
    #
    # @yield Code processing the batches
    def find_each(attributes_index: {})
      find_in_batches(:attributes_index => attributes_index) do |batch|
        batch.each do |item|
          yield(item)
        end
      end
    end
  end
end
