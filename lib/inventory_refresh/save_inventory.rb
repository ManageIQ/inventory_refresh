require "inventory_refresh/save_collection/recursive"
require "inventory_refresh/save_collection/topological_sort"

module InventoryRefresh
  class SaveInventory
    class << self
      include Logging

      # Saves the passed InventoryCollection objects
      #
      # @param ems [ExtManagementSystem] manager owning the inventory_collections
      # @param inventory_collections [Array<InventoryRefresh::InventoryCollection>] array of InventoryCollection objects
      #        for saving
      def save_inventory(ems, inventory_collections, strategy = nil)
        logger.debug("#{log_header(ems)} Scanning Inventory Collections...Start")
        InventoryRefresh::InventoryCollection::Scanner.scan!(inventory_collections)
        logger.debug("#{log_header(ems)} Scanning Inventory Collections...Complete")

        logger.info("#{log_header(ems)} Saving EMS Inventory...")

        if strategy.try(:to_sym) == :recursive
          InventoryRefresh::SaveCollection::Recursive.save_collections(ems, inventory_collections)
        else
          InventoryRefresh::SaveCollection::TopologicalSort.save_collections(ems, inventory_collections)
        end

        logger.info("#{log_header(ems)} Saving EMS Inventory...Complete")
        ems
      end

      private

      # @param ems [ExtManagementSystem] manager owning the inventory_collections
      # @return [String] helper string for logging
      def log_header(ems)
        "EMS: [#{ems.name}], id: [#{ems.id}]"
      end
    end
  end
end
