require_relative "test_builder"
require_relative "test_builder/persister_helper"

class TestPersister < InventoryRefresh::Persister
  attr_reader :manager, :target, :collections, :options

  include ::TestBuilder::PersisterHelper

  # @return [Config::Options] Options for the manager type
  def options
    @options ||= {}
  end

  def initialize(manager, target = nil, extra_options = {})
    @manager = manager
    @target  = target

    @collections = {}
    @options     = extra_options

    initialize_inventory_collections
  end
end
