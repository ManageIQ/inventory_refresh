require "inventory_refresh/logging"
require "inventory_refresh/save_collection/saver/batch"
require "inventory_refresh/save_collection/saver/concurrent_safe_batch"
require "inventory_refresh/save_collection/saver/default"

module InventoryRefresh::SaveCollection
  class Base
    class << self
      include InventoryRefresh::Logging

      # Saves one InventoryCollection object into the DB.
      #
      # @param ems [ExtManagementSystem] manger owning the InventoryCollection object
      # @param inventory_collection [InventoryRefresh::InventoryCollection] InventoryCollection object we want to save
      def save_inventory_object_inventory(ems, inventory_collection)
        return if skip?(inventory_collection)

        logger.debug("----- BEGIN ----- Saving collection #{inventory_collection} of size #{inventory_collection.size} to"\
                     " the database, for the manager: '#{ems.name}'...")

        if inventory_collection.custom_save_block.present?
          logger.debug("Saving collection #{inventory_collection} using a custom save block")
          inventory_collection.custom_save_block.call(ems, inventory_collection)
        else
          save_inventory(inventory_collection)
        end
        logger.debug("----- END ----- Saving collection #{inventory_collection}, for the manager: '#{ems.name}'...Complete")
        inventory_collection.saved = true
      end

      private

      # Returns true and sets collection as saved, if the collection should be skipped.
      #
      # @param inventory_collection [InventoryRefresh::InventoryCollection] InventoryCollection object we want to save
      # @return [Boolean] True if processing of the collection should be skipped
      def skip?(inventory_collection)
        if inventory_collection.noop?
          logger.debug("Skipping #{inventory_collection} because it results to noop.")
          inventory_collection.saved = true
          return true
        end

        false
      end

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
