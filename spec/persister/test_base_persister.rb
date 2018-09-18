require_relative "test_builder"
require_relative "test_builder/persister_helper"

class TestBasePersister < InventoryRefresh::Persister
  attr_reader :manager, :target, :collections

  include ::TestBuilder::PersisterHelper

  # @param _manager [ManageIQ::Providers::BaseManager] A manager object
  # @param _target [Object] A refresh Target object
  def initialize(_manager, _target = nil)
    super
  end

  # @return [Config::Options] Options for the manager type
  def options
    @options ||= {}
  end
end
