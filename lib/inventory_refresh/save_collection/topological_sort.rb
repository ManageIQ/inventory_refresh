require "inventory_refresh/logging"
require "inventory_refresh/inventory_collection/graph"
require "inventory_refresh/save_collection/base"

module InventoryRefresh::SaveCollection
  class TopologicalSort < InventoryRefresh::SaveCollection::Base
    class << self
      # Saves the passed InventoryCollection objects by doing a topology sort of the graph, then going layer by layer
      # and saving InventoryCollection object in each layer.
      #
      # @param ems [ExtManagementSystem] manager owning the inventory_collections
      # @param inventory_collections [Array<InventoryRefresh::InventoryCollection>] array of InventoryCollection objects
      #        for saving
      def save_collections(ems, inventory_collections)
        graph = InventoryRefresh::InventoryCollection::Graph.new(inventory_collections)
        graph.build_directed_acyclic_graph!

        layers = InventoryRefresh::Graph::TopologicalSort.new(graph).topological_sort

        logger.debug("Saving manager #{ems.name}...")

        sorted_graph_log = "Topological sorting of manager #{ems.name} resulted in these layers processable in parallel:\n"
        sorted_graph_log += graph.to_graphviz(:layers => layers)
        logger.debug(sorted_graph_log)

        layers.each_with_index do |layer, index|
          logger.debug("Saving manager #{ems.name} | Layer #{index}")
          layer.each do |inventory_collection|
            save_inventory_object_inventory(ems, inventory_collection) unless inventory_collection.saved?
          end
          logger.debug("Saved manager #{ems.name} | Layer #{index}")
        end

        logger.debug("Saving manager #{ems.name}...Complete")
      end
    end
  end
end
