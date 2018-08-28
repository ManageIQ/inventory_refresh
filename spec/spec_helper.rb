if ENV['CI']
  require 'simplecov'
  SimpleCov.start
end

require "inventory_refresh"
