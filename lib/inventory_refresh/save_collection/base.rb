require "inventory_refresh/save_collection/saver/batch"
require "inventory_refresh/save_collection/saver/concurrent_safe"
require "inventory_refresh/save_collection/saver/concurrent_safe_batch"
require "inventory_refresh/save_collection/saver/default"

module InventoryRefresh::SaveCollection
  class Base
    class << self
      # Saves one InventoryCollection object into the DB.
      #
      # @param ems [ExtManagementSystem] manger owning the InventoryCollection object
      # @param inventory_collection [InventoryRefresh::InventoryCollection] InventoryCollection object we want to save
      def save_inventory_object_inventory(ems, inventory_collection)
        #_log.debug("Saving collection #{inventory_collection} of size #{inventory_collection.size} to"\
        #           " the database, for the manager: '#{ems.name}'...")

        if inventory_collection.custom_save_block.present?
          #_log.debug("Saving collection #{inventory_collection} using a custom save block")
          inventory_collection.custom_save_block.call(ems, inventory_collection)
        else
          save_inventory(inventory_collection)
        end
        #_log.debug("Saving collection #{inventory_collection}, for the manager: '#{ems.name}'...Complete")
        inventory_collection.saved = true
      end

      private

      # Saves one InventoryCollection object into the DB using a configured saver_strategy class.
      #
      # @param inventory_collection [InventoryRefresh::InventoryCollection] InventoryCollection object we want to save
      def save_inventory(inventory_collection)
        saver_class = "InventoryRefresh::SaveCollection::Saver::#{inventory_collection.saver_strategy.to_s.camelize}"
        saver_class.constantize.new(inventory_collection).save_inventory_collection!
      end
    end
  end
end
