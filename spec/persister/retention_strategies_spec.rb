require_relative '../helpers/spec_mocked_data'
require_relative '../helpers/spec_parsed_data'
require_relative 'targeted_refresh_spec_helper'

describe InventoryRefresh::Persister do
  include SpecMockedData
  include SpecParsedData
  include TargetedRefreshSpecHelper

  ######################################################################################################################
  # Spec scenarios for various retentions_strategies, causing non existent records to be deleted or archived
  ######################################################################################################################
  #
  before do
    @ems = FactoryBot.create(:ems_cloud,
                              :network_manager => FactoryBot.create(:ems_network))
  end

  before do
    initialize_mocked_records

    # We want inventory without templates for the tests, so those don't affect our Hardware counts
    MiqTemplate.all.destroy_all
  end

  context "testing delete_complement" do
    [{:saver_strategy => 'batch'}, {:saver_strategy => 'concurrent_safe_batch'}].each do |extra_options|
      it "archives the data with :retention_strategy => 'archive' and different values of all_manager_uuids" do
        %i(nil blank filled).each do |all_manager_uuids_status|
          Vm.destroy_all
          persister = create_persister(extra_options.merge(:retention_strategy => "archive"))

          vm1 = FactoryBot.create(:vm_cloud, vm_data(1).merge(:ext_management_system => @ems))
          vm2 = FactoryBot.create(:vm_cloud, vm_data(2).merge(:ext_management_system => @ems))

          persister.vms.build(vm_data(3))

          persister.vms.all_manager_uuids = case all_manager_uuids_status
                                            when :nil    then nil
                                            when :blank  then []
                                            when :filled then [{ 'ems_ref' => vm1.ems_ref }]
                                            end

          persister.persist!

          active_persisted = case all_manager_uuids_status
                             when :nil then [vm_data(1)[:ems_ref], vm_data(2)[:ems_ref], vm_data(3)[:ems_ref]]
                             when :blank then [vm_data(3)[:ems_ref]]
                             when :filled then [vm_data(1)[:ems_ref], vm_data(3)[:ems_ref]]
                             end

          expect(Vm.active.pluck(:ems_ref)).to(
            match_array(active_persisted)
          )
        end
      end

      context "with :all_manager_uuids_scope" do
        it "archives the data with :retention_strategy => 'archive'" do
          Vm.destroy_all
          persister = create_persister(extra_options.merge(:retention_strategy => "archive"))

          subscription1 = FactoryBot.create(:subscription, :ems_ref => "subscription1", :ext_management_system => @ems)
          subscription2 = FactoryBot.create(:subscription, :ems_ref => "subscription2", :ext_management_system => @ems)

          region1 = FactoryBot.create(:source_region, :ems_ref => "region1", :ext_management_system => @ems)
          region2 = FactoryBot.create(:source_region, :ems_ref => "region2", :ext_management_system => @ems)
          region3 = FactoryBot.create(:source_region, :ems_ref => "region3", :ext_management_system => @ems)

          vm1 = FactoryBot.create(:vm_cloud,
                                   vm_data(1).merge(
                                     :ext_management_system => @ems,
                                     :subscription          => subscription1,
                                     :source_region         => region1,
                                   ))
          _vm2 = FactoryBot.create(:vm_cloud,
                                    vm_data(2).merge(
                                      :ext_management_system => @ems,
                                      :subscription          => subscription2,
                                      :source_region         => region2,
                                    ))
          _vm3 = FactoryBot.create(:vm_cloud,
                                    vm_data(3).merge(
                                      :ext_management_system => @ems,
                                      :subscription          => subscription2,
                                      :source_region         => region3,
                                    ))
          _vm4 = FactoryBot.create(:vm_cloud,
                                    vm_data(4).merge(
                                      :ext_management_system => @ems,
                                      :subscription          => subscription2,
                                      :source_region         => region1,
                                    ))
          _vm5 = FactoryBot.create(:vm_cloud,
                                    vm_data(5).merge(
                                      :ext_management_system => @ems,
                                      :subscription          => subscription1,
                                      :source_region         => region2,
                                    ))
          _vm6 = FactoryBot.create(:vm_cloud,
                                    vm_data(6).merge(
                                      :ext_management_system => @ems,
                                      :subscription          => subscription1,
                                      :source_region         => region1,
                                    ))

          expect(Vm.active.pluck(:ems_ref)).to(
            match_array([vm_data(1)[:ems_ref], vm_data(2)[:ems_ref], vm_data(3)[:ems_ref], vm_data(4)[:ems_ref],
                         vm_data(5)[:ems_ref], vm_data(6)[:ems_ref]])
          )
          expect(Vm.archived.pluck(:ems_ref)).to(
            match_array([])
          )

          persister.vms.build(vm_data(3))

          persister.vms.all_manager_uuids       = [{'ems_ref' => vm1.ems_ref}]
          persister.vms.all_manager_uuids_scope = [
            {:source_region => persister.source_regions.lazy_find("region1"), :subscription => persister.subscriptions.lazy_find("subscription1")},
            {:source_region => persister.source_regions.lazy_find("region2"), :subscription => persister.subscriptions.lazy_find("subscription1")}
          ]

          persister.persist!

          expect(Vm.active.pluck(:ems_ref)).to(
            match_array([vm_data(1)[:ems_ref], vm_data(2)[:ems_ref], vm_data(3)[:ems_ref], vm_data(4)[:ems_ref]])
          )
          expect(Vm.archived.pluck(:ems_ref)).to(
            match_array([vm_data(5)[:ems_ref], vm_data(6)[:ems_ref]])
          )
        end

        it "fails if all_manager_uuids_scope is using wrong relation" do
          persister = create_persister(extra_options.merge(:retention_strategy => "archive"))

          persister.vms.all_manager_uuids       = []
          persister.vms.all_manager_uuids_scope = [
            {:non_existent_relation => persister.source_regions.lazy_find("region1"), :subscription => persister.subscriptions.lazy_find("subscription1")},
            {:non_existent_relation => persister.source_regions.lazy_find("region2"), :subscription => persister.subscriptions.lazy_find("subscription1")}
          ]

          expect { persister.persist! }.to(
            raise_error("'InventoryCollection:<Vm>, blacklist: [genealogy_parent], strategy: local_db_find_missing_references' doesn't have relation :non_existent_relation provided in :all_manager_uuids_scope.")
          )
        end

        it "fails if all_manager_uuids_scope is pointing to the wrong value" do
          persister = create_persister(extra_options.merge(:retention_strategy => "archive"))

          persister.vms.all_manager_uuids       = []
          persister.vms.all_manager_uuids_scope = [
            {:source_region => persister.source_regions.lazy_find("region1_fake", :key => :name), :subscription => persister.subscriptions.lazy_find("subscription1")},
            {:source_region => persister.source_regions.lazy_find("region2"), :subscription => persister.subscriptions.lazy_find("subscription1")}
          ]

          expect { persister.persist! }.to(
            raise_error("'InventoryCollection:<Vm>, blacklist: [genealogy_parent], strategy: local_db_find_missing_references'"\
                        " couldn't load scope value :source_region => InventoryObjectLazy:('region1_fake',"\
                        " InventoryCollection:<SourceRegion>, strategy: local_db_find_missing_references,"\
                        " ref: manager_ref, key: name) provided in :all_manager_uuids_scope")
          )
        end

        it "fails if all_manager_uuids_scope have inconsistent keys" do
          _region1 = FactoryBot.create(:source_region, :ems_ref => "region1", :ext_management_system => @ems)

          persister = create_persister(extra_options.merge(:retention_strategy => "archive"))

          persister.vms.all_manager_uuids       = []
          persister.vms.all_manager_uuids_scope = [
            {:source_region => persister.source_regions.lazy_find("region1")},
            {:source_region => persister.source_regions.lazy_find("region2"), :subscription => persister.subscriptions.lazy_find("subscription1")}
          ]

          expect { persister.persist! }.to(
            raise_error("'InventoryCollection:<Vm>, blacklist: [genealogy_parent], strategy: local_db_find_missing_references'"\
                        " expected keys for :all_manager_uuids_scope are [:source_region], got [:source_region, :subscription]."\
                        " Keys must be the same for all scopes provided.")
          )
        end
      end

      context "not providing nested hardware, disks and networks" do
        it "archives the data with :retention_strategy => 'archive' and with #{extra_options}" do
          persister = create_persister(extra_options.merge(:retention_strategy => "archive"))

          all_network_port_uuids, all_vm_uuids = build_data_without_nested_refs(persister)

          # Delete the complement of what we've built
          persister.vms.all_manager_uuids           = all_vm_uuids
          persister.network_ports.all_manager_uuids = all_network_port_uuids

          persister.persist!

          expect(Vm.active.pluck(:ems_ref)).to(
            match_array([vm_data(1)[:ems_ref], vm_data(2)[:ems_ref], vm_data(60)[:ems_ref]])
          )
          expect(Vm.archived.pluck(:ems_ref)).to(
            match_array([vm_data(12)[:ems_ref], vm_data(4)[:ems_ref]])
          )

          expect(NetworkPort.active.pluck(:ems_ref)).to(
            match_array([network_port_data(1)[:ems_ref], network_port_data(2)[:ems_ref], network_port_data(60)[:ems_ref]])
          )
          expect(@ems.network_ports.archived.pluck(:ems_ref)).to(
            match_array([network_port_data(12)[:ems_ref], network_port_data(4)[:ems_ref]])
          )

          # The vm(12) gets archived, but we don't propagate to nested models, so active_hardwares returns 1
          assert_counts(
            :active_disks           => 2,
            :active_hardwares       => 1,
            :active_network_ports   => 3,
            :active_networks        => 2,
            :active_vms             => 3,
            :archived_disks         => 2,
            :archived_hardwares     => 2,
            :archived_network_ports => 2,
            :archived_networks      => 2,
            :archived_vms           => 2,
          )
        end

        it "destroys the data with :retention_strategy => 'destroy' and with #{extra_options}" do
          persister = create_persister(extra_options.merge(:retention_strategy => "destroy"))

          all_network_port_uuids, all_vm_uuids = build_data_without_nested_refs(persister)

          # Delete the complement of what we've built
          persister.vms.all_manager_uuids           = all_vm_uuids
          persister.network_ports.all_manager_uuids = all_network_port_uuids

          persister.persist!

          expect(Vm.pluck(:ems_ref)).to(
            match_array([vm_data(1)[:ems_ref], vm_data(2)[:ems_ref], vm_data(60)[:ems_ref]])
          )
          expect(NetworkPort.pluck(:ems_ref)).to(
            match_array([network_port_data(1)[:ems_ref], network_port_data(2)[:ems_ref], network_port_data(60)[:ems_ref]])
          )

          assert_counts(
            :active_disks           => 0,
            :active_hardwares       => 0,
            :active_network_ports   => 3,
            :active_networks        => 0,
            :active_vms             => 3,
            :archived_disks         => 0,
            :archived_hardwares     => 0,
            :archived_network_ports => 0,
            :archived_networks      => 0,
            :archived_vms           => 0,
          )
        end
      end

      context "providing nested hardware, disks and networks" do
        it "archives the data with :retention_strategy => 'archive' and with #{extra_options}" do
          persister = create_persister(extra_options.merge(:retention_strategy => "archive"))

          all_network_port_uuids, all_vm_uuids = build_data_with_nested_refs(persister)

          # Delete the complement of what we've built
          persister.vms.all_manager_uuids           = all_vm_uuids
          persister.network_ports.all_manager_uuids = all_network_port_uuids

          persister.persist!

          expect(Vm.active.pluck(:ems_ref)).to(
            match_array([vm_data(1)[:ems_ref], vm_data(2)[:ems_ref], vm_data(60)[:ems_ref]])
          )
          expect(Vm.archived.pluck(:ems_ref)).to(
            match_array([vm_data(12)[:ems_ref], vm_data(4)[:ems_ref]])
          )

          expect(NetworkPort.active.pluck(:ems_ref)).to(
            match_array([network_port_data(1)[:ems_ref], network_port_data(2)[:ems_ref], network_port_data(60)[:ems_ref]])
          )
          expect(@ems.network_ports.archived.pluck(:ems_ref)).to(
            match_array([network_port_data(12)[:ems_ref], network_port_data(4)[:ems_ref]])
          )

          # Skeletal precreate is causing the lazy linked models to be created
          active_hardwares = if extra_options[:saver_strategy] == "batch"
                               1
                             elsif extra_options[:saver_strategy] == "concurrent_safe_batch"
                               2
                             end

          assert_counts(
            :active_disks           => 2,
            :active_hardwares       => active_hardwares,
            :active_network_ports   => 3,
            :active_networks        => 2,
            :active_vms             => 3,
            :archived_disks         => 2,
            :archived_hardwares     => 2,
            :archived_network_ports => 2,
            :archived_networks      => 2,
            :archived_vms           => 2,
          )
        end

        it "destroys the data with :retention_strategy => 'destroy' and with #{extra_options}" do
          persister = create_persister(extra_options.merge(:retention_strategy => "destroy"))

          all_network_port_uuids, all_vm_uuids = build_data_with_nested_refs(persister)

          # Delete the complement of what we've built
          persister.vms.all_manager_uuids           = all_vm_uuids
          persister.network_ports.all_manager_uuids = all_network_port_uuids

          persister.persist!

          expect(Vm.pluck(:ems_ref)).to(
            match_array([vm_data(1)[:ems_ref], vm_data(2)[:ems_ref], vm_data(60)[:ems_ref]])
          )
          expect(NetworkPort.pluck(:ems_ref)).to(
            match_array([network_port_data(1)[:ems_ref], network_port_data(2)[:ems_ref], network_port_data(60)[:ems_ref]])
          )

          assert_result_with_nested_refs_and_destroy(extra_options)
        end

        it "checks delete_complement acts the same as full refresh with :retention_strategy => 'destroy'" do
          persister = create_persister(extra_options.merge(:retention_strategy => "destroy", :targeted => false))

          build_data_with_nested_refs(persister)

          # Full refresh, that will also delete the complement of what we've built by design of full refresh
          persister.persist!

          expect(Vm.pluck(:ems_ref)).to(
            match_array([vm_data(1)[:ems_ref], vm_data(2)[:ems_ref], vm_data(60)[:ems_ref]])
          )
          expect(NetworkPort.pluck(:ems_ref)).to(
            match_array([network_port_data(1)[:ems_ref], network_port_data(2)[:ems_ref], network_port_data(60)[:ems_ref]])
          )

          assert_result_with_nested_refs_and_destroy(extra_options)
        end
      end
    end
  end

  [{:saver_strategy => :default}, {:saver_strategy => :batch}].each do |extra_options|
    it "test legacy refresh deleting with :retention_strategy => nil and with options: #{extra_options}" do
      persister = create_persister(extra_options.merge(:retention_strategy => nil, :targeted => false))

      build_data_without_nested_refs(persister)

      # Full refresh
      persister.persist!

      expect(Vm.where.not(:ems_id => nil).pluck(:ems_ref)).to(
        match_array([vm_data(1)[:ems_ref], vm_data(2)[:ems_ref], vm_data(60)[:ems_ref]])
      )
      expect(NetworkPort.pluck(:ems_ref)).to(
        match_array([network_port_data(1)[:ems_ref], network_port_data(2)[:ems_ref], network_port_data(60)[:ems_ref]])
      )

      assert_counts(
        :active_disks           => 2,
        :active_hardwares       => 1,
        :active_network_ports   => 3,
        :active_networks        => 2,
        :active_vms             => 5,
        :archived_disks         => 0,
        :archived_hardwares     => 0,
        :archived_network_ports => 0,
        :archived_networks      => 0,
        :archived_vms           => 0,
      )
    end
  end

  it "checks delete_complement works only for batch strategies" do
    persister = create_persister(:retention_strategy => "destroy", :saver_strategy => 'default')

    all_vm_uuids                    = [persister.vms.build(vm_data(1)).uuid]
    persister.vms.all_manager_uuids = all_vm_uuids

    expect { persister.persist! }.to(
      raise_error(":delete_complement method is supported only for :saver_strategy => [:batch, :concurrent_safe_batch]")
    )
  end

  it "checks valid retentions strategies" do
    expect do
      create_persister(:retention_strategy => "made_up_name", :saver_strategy => 'batch')
    end.to(
      raise_error("Unknown InventoryCollection retention strategy: :made_up_name, allowed strategies are :destroy and :archive")
    )
  end

  def assert_counts(counts)
    expect(model_counts).to match(counts)
  end

  def model_counts
    {
      :active_vms             => Vm.active.count,
      :archived_vms           => Vm.archived.count,
      :active_network_ports   => NetworkPort.active.count,
      :archived_network_ports => NetworkPort.archived.count,
      :active_hardwares       => Hardware.active.count,
      :archived_hardwares     => Hardware.archived.count,
      :active_disks           => Disk.active.count,
      :archived_disks         => Disk.archived.count,
      :active_networks        => Network.active.count,
      :archived_networks      => Network.archived.count
    }
  end

  def build_data_with_nested_refs(persister)
    # Assert the starting state
    expect(Vm.active.pluck(:ems_ref)).to(
      match_array([vm_data(1)[:ems_ref], vm_data(12)[:ems_ref], vm_data(2)[:ems_ref], vm_data(4)[:ems_ref]])
    )
    expect(Vm.archived.pluck(:ems_ref)).to(
      match_array([])
    )

    expect(NetworkPort.active.pluck(:ems_ref)).to(
      match_array([network_port_data(1)[:ems_ref], network_port_data(12)[:ems_ref], network_port_data(2)[:ems_ref], network_port_data(4)[:ems_ref]])
    )
    expect(@ems.network_ports.archived.pluck(:ems_ref)).to(
      match_array([])
    )

    assert_counts(
      :active_disks           => 4,
      :active_hardwares       => 3,
      :active_network_ports   => 4,
      :active_networks        => 4,
      :active_vms             => 4,
      :archived_disks         => 0,
      :archived_hardwares     => 0,
      :archived_network_ports => 0,
      :archived_networks      => 0,
      :archived_vms           => 0,
    )

    lazy_find_vm1        = persister.vms.lazy_find(:ems_ref => vm_data(1)[:ems_ref])
    lazy_find_vm2        = persister.vms.lazy_find(:ems_ref => vm_data(2)[:ems_ref])
    lazy_find_vm60       = persister.vms.lazy_find(:ems_ref => vm_data(60)[:ems_ref])
    lazy_find_hardware1  = persister.hardwares.lazy_find(:vm_or_template => lazy_find_vm1)
    lazy_find_hardware2  = persister.hardwares.lazy_find(:vm_or_template => lazy_find_vm2)
    lazy_find_hardware60 = persister.hardwares.lazy_find(:vm_or_template => lazy_find_vm60)

    lazy_find_network1 = persister.networks.lazy_find(
      {:hardware => lazy_find_hardware1, :description => "public"},
      {:key     => :hostname,
       :default => 'default_value_unknown'}
    )

    lazy_find_network2 = persister.networks.lazy_find(
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
      :flavor   => persister.flavors.lazy_find(:ems_ref => flavor_data(1)[:name]),
      :location => lazy_find_network1,
    )

    vm_data2 = vm_data(2).merge(
      :flavor   => persister.flavors.lazy_find(:ems_ref => flavor_data(1)[:name]),
      :location => lazy_find_network2,
    )

    vm_data60 = vm_data(60).merge(
      :flavor   => persister.flavors.lazy_find(:ems_ref => flavor_data(1)[:name]),
      :location => lazy_find_network60,
    )

    all_network_port_uuids = []
    all_network_port_uuids << persister.network_ports.build(network_port_data(1).merge(:device => lazy_find_vm1)).uuid
    all_network_port_uuids << persister.network_ports.build(network_port_data(2).merge(:device => lazy_find_vm2)).uuid
    all_network_port_uuids << persister.network_ports.build(network_port_data(60).merge(:device => lazy_find_vm60)).uuid

    all_vm_uuids = []
    all_vm_uuids << persister.vms.build(vm_data1).uuid
    all_vm_uuids << persister.vms.build(vm_data2).uuid
    all_vm_uuids << persister.vms.build(vm_data60).uuid

    return all_network_port_uuids, all_vm_uuids
  end

  def build_data_without_nested_refs(persister)
    # Assert the starting state
    expect(Vm.active.pluck(:ems_ref)).to(
      match_array([vm_data(1)[:ems_ref], vm_data(12)[:ems_ref], vm_data(2)[:ems_ref], vm_data(4)[:ems_ref]])
    )
    expect(Vm.archived.pluck(:ems_ref)).to(
      match_array([])
    )

    expect(NetworkPort.active.pluck(:ems_ref)).to(
      match_array([network_port_data(1)[:ems_ref], network_port_data(12)[:ems_ref], network_port_data(2)[:ems_ref], network_port_data(4)[:ems_ref]])
    )
    expect(@ems.network_ports.archived.pluck(:ems_ref)).to(
      match_array([])
    )

    assert_counts(
      :active_disks           => 4,
      :active_hardwares       => 3,
      :active_network_ports   => 4,
      :active_networks        => 4,
      :active_vms             => 4,
      :archived_disks         => 0,
      :archived_hardwares     => 0,
      :archived_network_ports => 0,
      :archived_networks      => 0,
      :archived_vms           => 0,
    )

    lazy_find_vm1  = persister.vms.lazy_find(:ems_ref => vm_data(1)[:ems_ref])
    lazy_find_vm2  = persister.vms.lazy_find(:ems_ref => vm_data(2)[:ems_ref])
    lazy_find_vm60 = persister.vms.lazy_find(:ems_ref => vm_data(60)[:ems_ref])

    vm_data1  = vm_data(1)
    vm_data2  = vm_data(2)
    vm_data60 = vm_data(60)

    all_network_port_uuids = []
    all_network_port_uuids << persister.network_ports.build(network_port_data(1).merge(:device => lazy_find_vm1)).uuid
    all_network_port_uuids << persister.network_ports.build(network_port_data(2).merge(:device => lazy_find_vm2)).uuid
    all_network_port_uuids << persister.network_ports.build(network_port_data(60).merge(:device => lazy_find_vm60)).uuid

    all_vm_uuids = []
    all_vm_uuids << persister.vms.build(vm_data1).uuid
    all_vm_uuids << persister.vms.build(vm_data2).uuid
    all_vm_uuids << persister.vms.build(vm_data60).uuid

    return all_network_port_uuids, all_vm_uuids
  end

  def assert_result_with_nested_refs_and_destroy(extra_options)
    # Skeletal precreate is causing the lazy linked models to be created
    active_hardwares = if extra_options[:saver_strategy] == "batch"
                         0
                       elsif extra_options[:saver_strategy] == "concurrent_safe_batch"
                         3
                       end

    assert_counts(
      :active_disks           => 0,
      :active_hardwares       => active_hardwares,
      :active_network_ports   => 3,
      :active_networks        => 0,
      :active_vms             => 3,
      :archived_disks         => 0,
      :archived_hardwares     => 0,
      :archived_network_ports => 0,
      :archived_networks      => 0,
      :archived_vms           => 0,
    )
  end
end
