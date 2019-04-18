require_relative '../helpers/test_persister/cloud'
require_relative '../helpers/test_persister/containers'

module TargetedRefreshSpecHelper
  def create_persister(extra_options = {})
    TestPersister::Cloud.new(@ems, extra_options)
  end

  def create_containers_persister(extra_options = {})
    TestPersister::Containers.new(@ems, extra_options)
  end

  def expected_ext_management_systems_count
    2
  end

  def base_inventory_counts
    {
      :disk                         => 0,
      :ext_management_system        => expected_ext_management_systems_count,
      :flavor                       => 0,
      :hardware                     => 0,
      :miq_template                 => 0,
      :network                      => 0,
      :network_port                 => 0,
      :orchestration_stack          => 0,
      :orchestration_stack_resource => 0,
      :vm                           => 0,
      :vm_or_template               => 0
    }
  end

  def base_inventory_counts_containers
    {
      :container_group          => 0,
      :container_group_tags     => 0,
      :container_node           => 0,
      :container_project        => 0,
      :container_replicator     => 0,
      :container                => 0,
      :container_image          => 0,
      :container_image_registry => 0,
      :tags                     => 0
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
      :ext_management_system        => ExtManagementSystem.count,
      :flavor                       => Flavor.count,
      :vm_or_template               => VmOrTemplate.count,
      :vm                           => Vm.count,
      :miq_template                 => MiqTemplate.count,
      :disk                         => Disk.count,
      :hardware                     => Hardware.count,
      :network                      => Network.count,
      :orchestration_stack          => OrchestrationStack.count,
      :orchestration_stack_resource => OrchestrationStackResource.count,
      :network_port                 => NetworkPort.count,
    }
    expect(actual).to eq expected_table_counts
  end

  def assert_containers_table_counts(expected_table_counts)
    actual = {
      :container_group          => ContainerGroup.count,
      :container_group_tags     => ContainerGroupTag.count,
      :container_node           => ContainerNode.count,
      :container_project        => ContainerProject.count,
      :container_replicator     => ContainerReplicator.count,
      :container                => Container.count,
      :container_image          => ContainerImage.count,
      :container_image_registry => ContainerImageRegistry.count,
      :tags                     => Tag.count,
    }
    expect(actual).to eq expected_table_counts
  end

  def assert_ems(expected_table_counts)
    expect(@ems).to have_attributes(
      :api_version => nil, # TODO: Should be 3.0
      :uid_ems     => nil
    )
    expect(@ems.flavors.size).to eql(expected_table_counts[:flavor])
    expect(@ems.vms_and_templates.size).to eql(expected_table_counts[:vm_or_template])
    expect(@ems.network_ports.size).to eql(expected_table_counts[:network_port])
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
