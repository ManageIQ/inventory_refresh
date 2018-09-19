require_relative '../models/manageiq/providers/inventory/persister.rb'

class TestPersister < ManageIQ::Providers::Inventory::Persister
  def initialize_inventory_collections
    %i(vms
       miq_templates).each do |name|

      add_collection(cloud, name) do |builder|
        builder.add_properties(
          :secondary_refs => {:by_name => [:name], :by_uid_ems_and_name => %i(uid_ems name)}
        )
      end
    end

    add_key_pairs
    add_flavors

    %i(hardwares
       networks
       disks
       orchestration_stacks).each do |name|

      add_collection(cloud, name)
    end

    add_orchestration_stacks_resources
    add_network_ports
  end

  private

  # Cloud InventoryCollection
  def add_key_pairs
    add_collection(cloud, :key_pairs) do |builder|
      builder.add_properties(:manager_uuids => name_references(:key_pairs))
    end
  end

  # Cloud InventoryCollection
  def add_orchestration_stacks_resources
    add_collection(cloud, :orchestration_stacks_resources) do |builder|
      builder.add_properties(:secondary_refs => {:by_stack_and_ems_ref => %i(stack ems_ref)})
    end
  end

  # Cloud InventoryCollection
  def add_flavors
    add_collection(cloud, :flavors) do |builder|
      builder.add_properties(:strategy => :local_db_find_references)
    end
  end

  # Network InventoryCollection
  def add_network_ports
    add_collection(network, :network_ports) do |builder|
      builder.add_properties(
        :manager_uuids  => references(:vms) + references(:network_ports) + references(:load_balancers),
        :parent         => manager.network_manager,
        :secondary_refs => {:by_device => [:device], :by_device_and_name => %i(device name)}
      )
    end
  end

  def options
    {}
  end

  def targeted?
    true
  end

  def strategy
    :local_db_find_missing_references
  end

  def parent
    manager.presence
  end

  def shared_options
    {
      :strategy => strategy,
      :targeted => targeted?,
      :parent   => parent
    }
  end
end
