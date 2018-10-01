class TestBuilder < ::InventoryRefresh::InventoryCollection::Builder
  require_relative "test_builder/shared"
  include TestBuilder::Shared

  # Default options for builder
  #   :adv_settings
  #     - values from Advanced settings (doesn't overwrite values specified in code)
  #     - @see method ManageIQ::Providers::Inventory::Persister.make_builder_settings()
  #   :shared_properties
  #     - any properties applied if missing (not explicitly specified)
  def self.default_options
    super.merge(:adv_settings => {})
  end

  # @see prepare_data()
  def initialize(name, persister_class, options = self.class.default_options)
    super
    @adv_settings = options[:adv_settings] # Configuration/Advanced settings in GUI
  end

  # Builds data for InventoryCollection
  # Calls method @name (if exists) with specific properties
  # Yields for overwriting provider-specific properties
  def construct_data
    add_properties(@adv_settings, :if_missing)
    super
  end

  protected

  def ar_base_class
    ActiveRecord::Base
  end
end
