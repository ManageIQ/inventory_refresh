# require_relative 'test_persister'
require_relative 'test_containers_persister'

module TargetedRefreshSpecHelper
  def create_persister
    TestPersister.new(@ems, ManagerRefresh::TargetCollection.new(:manager => @ems))
  end

  def create_containers_persister
    TestContainersPersister.new(@ems, @ems)
  end

  def expected_ext_management_systems_count
    2
  end

  def base_inventory_counts
    {
      :auth_private_key              => 0,
      :availability_zone             => 0,
      :cloud_network                 => 0,
      :cloud_subnet                  => 0,
      :cloud_volume                  => 0,
      :cloud_volume_backup           => 0,
      :cloud_volume_snapshot         => 0,
      :custom_attribute              => 0,
      :disk                          => 0,
      :ext_management_system         => expected_ext_management_systems_count,
      :firewall_rule                 => 0,
      :flavor                        => 0,
      :floating_ip                   => 0,
      :guest_device                  => 0,
      :hardware                      => 0,
      :miq_template                  => 0,
      :network                       => 0,
      :network_port                  => 0,
      :network_router                => 0,
      :operating_system              => 0,
      :orchestration_stack           => 0,
      :orchestration_stack_output    => 0,
      :orchestration_stack_parameter => 0,
      :orchestration_stack_resource  => 0,
      :orchestration_template        => 0,
      :security_group                => 0,
      :snapshot                      => 0,
      :system_service                => 0,
      :vm                            => 0,
      :vm_or_template                => 0
    }
  end

  def base_inventory_counts_containers
    {
      :container_group          => 0,
      :container_node           => 0,
      :container_project        => 0,
      :container_replicator     => 0,
      :container                => 0,
      :container_image          => 0,
      :container_image_registry => 0,
    }
  end

  def assert_containers_counts(expected_table_counts)
    expected_counts = base_inventory_counts_containers.merge(expected_table_counts)
    assert_containers_table_counts(expected_counts)
    # assert_ems(expected_counts)
  end

  def assert_counts(expected_table_counts, expected_ems_table_counts = nil)
    expected_counts = base_inventory_counts.merge(expected_table_counts)
    expected_ems_table_counts ||= expected_counts
    expected_ems_counts = base_inventory_counts.merge(expected_ems_table_counts)

    assert_table_counts(expected_counts)
    assert_ems(expected_ems_counts)
  end

  def assert_table_counts(expected_table_counts)
    actual = {
      :auth_private_key              => AuthPrivateKey.count,
      :cloud_volume                  => CloudVolume.count,
      :cloud_volume_backup           => CloudVolumeBackup.count,
      :cloud_volume_snapshot         => CloudVolumeSnapshot.count,
      :ext_management_system         => ExtManagementSystem.count,
      :flavor                        => Flavor.count,
      :availability_zone             => AvailabilityZone.count,
      :vm_or_template                => VmOrTemplate.count,
      :vm                            => Vm.count,
      :miq_template                  => MiqTemplate.count,
      :disk                          => Disk.count,
      :guest_device                  => GuestDevice.count,
      :hardware                      => Hardware.count,
      :network                       => Network.count,
      :operating_system              => OperatingSystem.count,
      :snapshot                      => Snapshot.count,
      :system_service                => SystemService.count,
      :orchestration_template        => OrchestrationTemplate.count,
      :orchestration_stack           => OrchestrationStack.count,
      :orchestration_stack_parameter => OrchestrationStackParameter.count,
      :orchestration_stack_output    => OrchestrationStackOutput.count,
      :orchestration_stack_resource  => OrchestrationStackResource.count,
      :security_group                => SecurityGroup.count,
      :firewall_rule                 => FirewallRule.count,
      :network_port                  => NetworkPort.count,
      :cloud_network                 => CloudNetwork.count,
      :floating_ip                   => FloatingIp.count,
      :network_router                => NetworkRouter.count,
      :cloud_subnet                  => CloudSubnet.count,
      :custom_attribute              => CustomAttribute.count
    }
    expect(actual).to eq expected_table_counts
  end

  def assert_containers_table_counts(expected_table_counts)
    actual = {
      :container_group          => ContainerGroup.count,
      :container_node           => ContainerNode.count,
      :container_project        => ContainerProject.count,
      :container_replicator     => ContainerReplicator.count,
      :container                => Container.count,
      :container_image          => ContainerImage.count,
      :container_image_registry => ContainerImageRegistry.count,
    }
    expect(actual).to eq expected_table_counts
  end

  def assert_ems(expected_table_counts)
    expect(@ems).to have_attributes(
      :api_version => nil, # TODO: Should be 3.0
      :uid_ems     => nil
    )
    expect(@ems.flavors.size).to eql(expected_table_counts[:flavor])
    expect(@ems.availability_zones.size).to eql(expected_table_counts[:availability_zone])
    expect(@ems.vms_and_templates.size).to eql(expected_table_counts[:vm_or_template])
    expect(@ems.security_groups.size).to eql(expected_table_counts[:security_group])
    expect(@ems.network_ports.size).to eql(expected_table_counts[:network_port])
    expect(@ems.cloud_networks.size).to eql(expected_table_counts[:cloud_network])
    expect(@ems.floating_ips.size).to eql(expected_table_counts[:floating_ip])
    expect(@ems.network_routers.size).to eql(expected_table_counts[:network_router])
    expect(@ems.cloud_subnets.size).to eql(expected_table_counts[:cloud_subnet])
    expect(@ems.miq_templates.size).to eq(expected_table_counts[:miq_template])

    expect(@ems.orchestration_stacks.size).to eql(expected_table_counts[:orchestration_stack])
  end

  def records_identities(arels)
    arels.transform_values! do |value|
      value.to_a.map { |x| {:id => x.id} }.sort_by { |x| x[:id] }
    end
  end

  def match_created(persister, records = {})
    match_records(persister, :created_records, records)
  end

  def match_updated(persister, records = {})
    match_records(persister, :updated_records, records)
  end

  def match_deleted(persister, records = {})
    match_records(persister, :deleted_records, records)
  end

  def persister_records_identities(persister, kind)
    persister.collections.map { |key, value| [key, value.send(kind)] if value.send(kind).present? }.compact.to_h.transform_values! do |value|
      value.sort_by { |x| x[:id] }
    end
  end

  def match_records(persister, kind, records)
    expect(
      persister_records_identities(persister, kind)
    ).to(
      match(records_identities(records))
    )
  end
end
