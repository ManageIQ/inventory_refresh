require "active_support/core_ext/module/delegation"

module InventoryRefresh
  class InventoryCollection
    class UnconnectedEdge
      attr_reader :inventory_object, :inventory_object_key, :inventory_object_lazy

      # @param inventory_object [InventoryRefresh::InventoryObject] InventoryObject that couldn't connect the relation
      # @param inventory_object_key [String] Relation name that couldn't be connected
      # @param inventory_object_lazy [InventoryRefresh::InventoryObjectLazy] The lazy relation that failed to load
      #                              this can happen only for relations with key, or pointing to DB only relations
      def initialize(inventory_object, inventory_object_key, inventory_object_lazy)
        @inventory_object      = inventory_object
        @inventory_object_key  = inventory_object_key
        @inventory_object_lazy = inventory_object_lazy
      end
    end
  end
end
