require "inventory_refresh/save_collection/topological_sort"
require "inventory_refresh/save_collection/sweeper"

module InventoryRefresh
  class SaveInventory
    class << self
      include Logging

      # Saves the passed InventoryCollection objects
      #
      # @param ems [ExtManagementSystem] manager owning the inventory_collections
      # @param inventory_collections [Array<InventoryRefresh::InventoryCollection>] array of InventoryCollection objects
      #        for saving
      def save_inventory(ems, inventory_collections)
        logger.debug("#{log_header(ems)} Scanning Inventory Collections...Start")
        InventoryRefresh::InventoryCollection::Scanner.scan!(inventory_collections)
        logger.debug("#{log_header(ems)} Scanning Inventory Collections...Complete")

        logger.info("#{log_header(ems)} Saving EMS Inventory...")
        InventoryRefresh::SaveCollection::TopologicalSort.save_collections(ems, inventory_collections)
        logger.info("#{log_header(ems)} Saving EMS Inventory...Complete")

        ems
      end

      # Sweeps inactive records based on :last_seen_at and :refresh_start timestamps. All records having :last_seen_at
      # lower than :refresh_start or nil will be archived/deleted.
      #
      # @param ems [ExtManagementSystem] manager owning the inventory_collections
      # @param inventory_collections [Array<InventoryRefresh::InventoryCollection>] array of InventoryCollection objects
      #        for sweeping
      # @param sweep_scope [Array<String, Symbol, Hash>] Array of inventory collection names marking sweep. Or for
      #        targeted sweeping it's array of hashes, where key is inventory collection name pointing to an array of
      #        identifiers of inventory objects we want to target for sweeping.
      # @param refresh_state [ActiveRecord] Record of :refresh_states
      def sweep_inactive_records(ems, inventory_collections, sweep_scope, refresh_state)
        inventory_collections.each do |inventory_collection|
          inventory_collection.strategy = :local_db_find_references
        end

        logger.info("#{log_header(ems)} Sweeping EMS Inventory with scope #{sweep_scope} and date #{refresh_state.created_at} ...")
        InventoryRefresh::SaveCollection::Sweeper.sweep(ems, inventory_collections, sweep_scope, refresh_state)
        logger.info("#{log_header(ems)} Sweeping EMS Inventory with scope #{sweep_scope} and date #{refresh_state.created_at}...Complete")

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
