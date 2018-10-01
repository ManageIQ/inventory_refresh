require_relative "test_builder"
require_relative "test_builder/persister_helper"

class TestPersister < InventoryRefresh::Persister
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

  # @return [Hash] entire Persister object serialized to hash
  def to_hash
    collections_data = collections.map do |_, collection|
      next if collection.data.blank?                              &&
              collection.targeted_scope.primary_references.blank? &&
              collection.all_manager_uuids.nil?                   &&
              collection.skeletal_primary_index.index_data.blank?

      collection.to_hash
    end.compact

    {
      :ems_id      => manager.id,
      :class       => self.class.name,
      :collections => collections_data
    }
  end

  class << self
    protected

    # Returns Persister object built from serialized data
    #
    # @param persister_data [Hash] serialized Persister object in hash
    # @return [ManageIQ::Providers::Inventory::Persister] Persister object built from serialized data
    def from_hash(persister_data)
      # Extract the specific Persister class
      persister_class = persister_data['class'].constantize
      unless persister_class < InventoryRefresh::Persister
        raise "Persister class must inherit from a InventoryRefresh::Persister"
      end

      # TODO(mslemr) Due to this find is persister connected ManageIQ class!
      ems = ManageIQ::Providers::BaseManager.find(persister_data['ems_id'])
      persister = persister_class.new(
        ems,
        InventoryRefresh::TargetCollection.new(:manager => ems) # TODO(lsmola) we need to pass serialized targeted scope here
      )

      persister_data['collections'].each do |collection|
        inventory_collection = persister.collections[collection['name'].try(:to_sym)]
        raise "Unrecognized InventoryCollection name: #{inventory_collection}" if inventory_collection.blank?

        inventory_collection.from_hash(collection, persister.collections)
      end
      persister
    end
  end
end
