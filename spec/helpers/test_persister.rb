require_relative "test_builder"
require_relative "test_builder/persister_helper"

class TestPersister < InventoryRefresh::Persister
  attr_reader :manager, :target, :collections

  include ::TestBuilder::PersisterHelper

  # @return [Config::Options] Options for the manager type
  def options
    @options ||= {}
  end
end
