require "inventory_refresh/save_collection/recursive"
require "inventory_refresh/save_collection/topological_sort"

module InventoryRefresh
  class SaveInventory
    class << self
      # Saves the passed InventoryCollection objects
      #
      # @param ems [ExtManagementSystem] manager owning the inventory_collections
      # @param inventory_collections [Array<InventoryRefresh::InventoryCollection>] array of InventoryCollection objects
      #        for saving
      def save_inventory(ems, inventory_collections)
        #_log.debug("#{log_header(ems)} Scanning Inventory Collections...Start")
        InventoryRefresh::InventoryCollection::Scanner.scan!(inventory_collections)
        #_log.debug("#{log_header(ems)} Scanning Inventory Collections...Complete")

        #_log.info("#{log_header(ems)} Saving EMS Inventory...")

        inventory_object_saving_strategy = Settings.ems_refresh[ems.class.ems_type].try(:[], :inventory_object_saving_strategy)
        if inventory_object_saving_strategy.try(:to_sym) == :recursive
          InventoryRefresh::SaveCollection::Recursive.save_collections(ems, inventory_collections)
        else
          InventoryRefresh::SaveCollection::TopologicalSort.save_collections(ems, inventory_collections)
        end

        #_log.info("#{log_header(ems)} Saving EMS Inventory...Complete")
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
