require_relative '../helpers/spec_mocked_data'
require_relative '../helpers/spec_parsed_data'
require_relative 'targeted_refresh_spec_helper'

describe InventoryRefresh::Persister do
  include SpecMockedData
  include SpecParsedData
  include TargetedRefreshSpecHelper

  ######################################################################################################################
  # Spec scenarios for deleting complement of passed uuids
  ######################################################################################################################
  #
  before do
    @ems = FactoryGirl.create(:ems_cloud,
                              :network_manager => FactoryGirl.create(:ems_network))
  end

  before do
    initialize_mocked_records
  end

  let(:persister) { create_persister }

  it "deletes the complement of passed data" do
    lazy_find_vm1        = persister.vms.lazy_find(:ems_ref => vm_data(1)[:ems_ref])
    lazy_find_vm2        = persister.vms.lazy_find(:ems_ref => vm_data(2)[:ems_ref])
    lazy_find_vm60       = persister.vms.lazy_find(:ems_ref => vm_data(60)[:ems_ref])
    lazy_find_hardware1  = persister.hardwares.lazy_find(:vm_or_template => lazy_find_vm1)
    lazy_find_hardware2  = persister.hardwares.lazy_find(:vm_or_template => lazy_find_vm2)
    lazy_find_hardware60 = persister.hardwares.lazy_find(:vm_or_template => lazy_find_vm60)

    lazy_find_network1  = persister.networks.lazy_find(
      {:hardware => lazy_find_hardware1, :description => "public"},
      {:key     => :hostname,
       :default => 'default_value_unknown'}
    )
    lazy_find_network2  = persister.networks.lazy_find(
      {:hardware => lazy_find_hardware2, :description => "public"},
      {:key     => :hostname,
       :default => 'default_value_unknown'}
    )
    lazy_find_network60 = persister.networks.lazy_find(
      {:hardware => lazy_find_hardware60, :description => "public"},
      {:key     => :hostname,
       :default => 'default_value_unknown'}
    )

    vm_data1 = vm_data(1).merge(
      :flavor           => persister.flavors.lazy_find(:ems_ref => flavor_data(1)[:name]),
      :genealogy_parent => persister.miq_templates.lazy_find(:ems_ref => image_data(1)[:ems_ref]),
      :key_pairs        => [persister.key_pairs.lazy_find(:name => key_pair_data(1)[:name])],
      :location         => lazy_find_network1,
    )

    vm_data2 = vm_data(2).merge(
      :flavor           => persister.flavors.lazy_find(:ems_ref => flavor_data(1)[:name]),
      :genealogy_parent => persister.miq_templates.lazy_find(:ems_ref => image_data(1)[:ems_ref]),
      :key_pairs        => [persister.key_pairs.lazy_find(:name => key_pair_data(1)[:name])],
      :location         => lazy_find_network2,
    )

    vm_data60              = vm_data(60).merge(
      :flavor           => persister.flavors.lazy_find(:ems_ref => flavor_data(1)[:name]),
      :genealogy_parent => persister.miq_templates.lazy_find(:ems_ref => image_data(1)[:ems_ref]),
      :key_pairs        => [persister.key_pairs.lazy_find(:name => key_pair_data(1)[:name])],
      :location         => lazy_find_network60,
    )
    all_network_port_uuids = []
    all_network_port_uuids << persister.network_ports.build(network_port_data(1).merge(:device => lazy_find_vm1)).uuid
    all_network_port_uuids << persister.network_ports.build(network_port_data(2).merge(:device => lazy_find_vm2)).uuid
    all_network_port_uuids << persister.network_ports.build(network_port_data(60).merge(:device => lazy_find_vm60)).uuid

    all_vm_uuids = []
    all_vm_uuids << persister.vms.build(vm_data1).uuid
    all_vm_uuids << persister.vms.build(vm_data2).uuid
    all_vm_uuids << persister.vms.build(vm_data60).uuid

    # Delete the complement of what we've built
    persister.vms.all_manager_uuids           = all_vm_uuids
    persister.network_ports.all_manager_uuids = all_network_port_uuids

    persister.persist!

    expect(Vm.active.pluck(:ems_ref)).to(
      match_array(
        [vm_data(1)[:ems_ref], vm_data(2)[:ems_ref], vm_data(60)[:ems_ref]]
      )
    )

    expect(NetworkPort.active.pluck(:ems_ref)).to(
      match_array(
        [network_port_data(1)[:ems_ref], network_port_data(2)[:ems_ref], network_port_data(60)[:ems_ref]]
      )
    )
  end
end
