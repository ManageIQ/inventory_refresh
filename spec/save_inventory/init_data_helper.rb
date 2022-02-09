require_relative "../helpers/test_persister"

module InitDataHelper
  def initialize_all_inventory_collections
    # Initialize the InventoryCollections
    all_collections.each do |collection|
      send("#{collection}_init_data")
    end
  end

  def initialize_inventory_collections(only_collections)
    # Initialize the InventoryCollections
    only_collections.each do |collection|
      send("#{collection}_init_data",
           :complete => false)
    end

    (all_collections - only_collections).each do |collection|
      send("#{collection}_init_data",
           :complete => false,
           :strategy => :local_db_cache_all)
    end
  end

  def orchestration_stacks_init_data(extra_attributes = {})
    # Shadowing the default blacklist so we have an automatically solved graph cycle
    @persister.add_collection(:orchestration_stacks, cloud, extra_attributes.merge(:attributes_blacklist => [])) do |builder|
      builder.add_properties(:model_class => ::ManageIQ::Providers::CloudManager::OrchestrationStack)
    end
  end

  def orchestration_stacks_resources_init_data(extra_attributes = {})
    # Shadowing the default blacklist so we have an automatically solved graph cycle
    @persister.add_collection(:orchestration_stacks_resources, cloud, extra_attributes)
  end

  def db_vms_init_data(extra_attributes = {})
    @persister.add_collection(:db_vms, cloud, extra_attributes.merge(:attributes_blacklist => [])) do |builder|
      builder.add_properties(
        :association => :vms,
        :model_class => ::Vm
      )
    end
  end

  def vms_init_data(extra_attributes = {})
    @persister.add_collection(:vms, cloud, extra_attributes.merge(:attributes_blacklist => []))
  end

  def miq_templates_init_data(extra_attributes = {})
    @persister.add_collection(:miq_templates, cloud, extra_attributes)
  end

  def key_pairs_init_data(extra_attributes = {})
    @persister.add_collection(:key_pairs, cloud, extra_attributes)
  end

  def hardwares_init_data(extra_attributes = {})
    @persister.add_collection(:hardwares, cloud, extra_attributes)
  end

  def disks_init_data(extra_attributes = {})
    @persister.add_collection(:disks, cloud, extra_attributes)
  end

  def network_ports_init_data(extra_attributes = {})
    @persister.add_collection(:network_ports, network, extra_attributes)
  end

  def db_network_ports_init_data(extra_attributes = {})
    @persister.add_collection(:db_network_ports, network, extra_attributes) do |builder|
      builder.add_properties(
        :association => :network_ports,
        :model_class => ::NetworkPort
      )
    end
  end

  def cloud
    TestBuilder::CloudManager
  end

  def network
    TestBuilder::NetworkManager
  end

  def persister_class
    TestPersister
  end

  def association_attributes(model_class)
    # All association attributes and foreign keys of the model
    model_class.reflect_on_all_associations.map { |x| [x.name, x.foreign_key] }.flatten.compact.map(&:to_sym)
  end

  def custom_association_attributes
    # These are associations that are not modeled in a standard rails way, e.g. the ancestry
    %i[parent genealogy_parent genealogy_parent_object]
  end
end
