module InventoryRefresh
  class << self
    attr_writer :logger
  end

  def self.logger
    @logger ||= NullLogger.new
  end

  module Logging
    def logger
      InventoryRefresh.logger
    end
  end
end
