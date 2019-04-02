require_relative '../test_persister'

class TestPersister::Cloud < ::TestPersister
  def initialize_inventory_collections
    %i(vms
       miq_templates).each do |name|

      add_collection(name, cloud) do |builder|
        builder.add_properties(
          :secondary_refs => {:by_name => [:name], :by_uid_ems_and_name => %i(uid_ems name)}
        )
      end
    end

    add_key_pairs
    add_flavors

    %i(source_regions
       subscriptions
       hardwares
       networks
       disks
       orchestration_stacks).each do |name|

      add_collection(name, cloud)
    end

    add_orchestration_stacks_resources
    add_network_ports
  end

  private

  # Cloud InventoryCollection
  def add_key_pairs
    add_collection(:key_pairs, cloud)
  end

  # Cloud InventoryCollection
  def add_orchestration_stacks_resources
    add_collection(:orchestration_stacks_resources, cloud) do |builder|
      builder.add_properties(:secondary_refs => {:by_stack_and_ems_ref => %i(stack ems_ref)})
    end
  end

  # Cloud InventoryCollection
  def add_flavors
    add_collection(:flavors, cloud) do |builder|
      builder.add_properties(:strategy => :local_db_find_references)
    end
  end

  # Network InventoryCollection
  def add_network_ports
    add_collection(:network_ports, network) do |builder|
      builder.add_properties(
        :parent         => manager.network_manager,
        :secondary_refs => {:by_device => [:device], :by_device_and_name => %i(device name)}
      )
    end
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

  def saver_strategy
    :default # TODO(lsmola) turn everything to concurrent_safe_batch
  end

  def shared_options
    super.merge(options)
  end
end
