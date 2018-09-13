module InventoryRefresh
  attr_writer :logger

  def self.logger
    @logger ||= NullLogger.new
  end

  module Logging
    def logger
      InventoryRefresh.logger
    end
  end
end
