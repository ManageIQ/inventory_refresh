require_relative "cloud_manager"
require_relative "network_manager"
require_relative "container_manager"

class TestBuilder
  module PersisterHelper
    extend ActiveSupport::Concern

    # builder_class for add_collection()
    def cloud
      ::TestBuilder::CloudManager
    end

    # builder_class for add_collection()
    def network
      ::TestBuilder::NetworkManager
    end

    def container
      ::TestBuilder::ContainerManager
    end

    # @param _extra_settings [Hash]
    def builder_settings(_extra_settings = {})
      opts = super
      opts[:adv_settings] = options.try(:[], :inventory_collections).try(:to_hash) || {}

      opts
    end

    # Returns list of target's ems_refs
    # @return [Array<String>]
    def references(collection)
      target.try(:references, collection) || []
    end

    # Returns list of target's name
    # @return [Array<String>]
    def name_references(collection)
      target.try(:name_references, collection) || []
    end
  end
end
