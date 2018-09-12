require "inventory_refresh/graph"
require "inventory_refresh/inventory_collection"
require "inventory_refresh/inventory_object"
require "inventory_refresh/inventory_object_lazy"
require "inventory_refresh/logging"
require "inventory_refresh/null_logger"
require "inventory_refresh/save_inventory"
require "inventory_refresh/target"
require "inventory_refresh/target_collection"
require "inventory_refresh/version"

module InventoryRefresh
  class << self
    attr_accessor :log
  end

  def self.log
    @log ||= NullLogger.new
  end
end
