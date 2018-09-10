require "forwardable"

module InventoryRefresh
  module Logging
    extend Forwardable
    delegate :log => :InventoryRefresh
  end
end
