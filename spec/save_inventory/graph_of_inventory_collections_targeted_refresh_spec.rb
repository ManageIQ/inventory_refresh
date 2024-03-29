require_relative 'spec_helper'
require_relative '../helpers/spec_parsed_data'
require_relative 'init_data_helper'

describe InventoryRefresh::SaveInventory do
  include SpecHelper
  include SpecParsedData
  include InitDataHelper

  ######################################################################################################################
  # Spec scenarios showing saving of the inventory with Targeted refresh strategy
  ######################################################################################################################

  before do
    @ems = FactoryBot.create(:ems_cloud)

    allow(@ems.class).to receive(:ems_type).and_return(:mock)
    @persister = persister_class.new(@ems, InventoryRefresh::TargetCollection.new(:manager => @ems))
  end

  it "refreshing all records and data collects everything" do
    # Get the relations
    initialize_all_inventory_collections
    initialize_inventory_collection_data

    # Invoke the InventoryCollections saving
    InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

    # Assert all data were filled
    load_records
    assert_everything_is_collected
  end

  it "do a targeted refresh that will only create and update a new vm, hardware and disks" do
    # Get the relations
    initialize_all_inventory_collections
    initialize_inventory_collection_data

    # Invoke the InventoryCollections saving
    InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

    # Assert all data were filled
    load_records
    assert_everything_is_collected

    ### Second refresh ###
    # Initialize the InventoryCollections and data for a new VM hardware and disks
    initialize_inventory_collections(%i[vms hardwares disks])

    @vm_data_3 = vm_data(3).merge(
      :key_pairs => [@persister.key_pairs.lazy_find(key_pair_data(2)[:name])]
    )
    @hardware_data_3 = hardware_data(3).merge(
      :guest_os       => @persister.hardwares.lazy_find(@persister.miq_templates.lazy_find(image_data(2)[:ems_ref]), :key => :guest_os),
      :vm_or_template => @persister.vms.lazy_find(vm_data(3)[:ems_ref])
    )
    @disk_data_3 = disk_data(3).merge(
      :hardware => @persister.hardwares.lazy_find(@persister.vms.lazy_find(vm_data(3)[:ems_ref]))
    )
    @disk_data_31 = disk_data(31).merge(
      :hardware => @persister.hardwares.lazy_find(@persister.vms.lazy_find(vm_data(3)[:ems_ref]))
    )

    # Fill InventoryCollections with data
    {
      :vms       => [@vm_data_3],
      :hardwares => [@hardware_data_3],
      :disks     => [@disk_data_3, @disk_data_31],
    }.each_pair do |inventory_collection_name, data_arr|
      data_arr.each do |data|
        @persister.send(inventory_collection_name).build(data)
      end
    end

    # Invoke the InventoryCollections saving
    InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

    load_records
    @vm3          = Vm.find_by(:ems_ref => "vm_ems_ref_3")
    @vm_hardware3 = Hardware.find_by(:vm_or_template => @vm3)
    @disk3        = Disk.find_by(:hardware => @vm_hardware3, :device_name => "disk_name_3")
    @disk31       = Disk.find_by(:hardware => @vm_hardware3, :device_name => "disk_name_31")

    expect(@vm3.hardware.id).to eq(@vm_hardware3.id)
    expect(@vm3.hardware.disks.pluck(:id)).to match_array([@disk3.id, @disk31.id])
    expect(@vm3.key_pairs.pluck(:id)).to match_array([@key_pair2.id])

    assert_everything_is_collected(
      :extra_vms      => [
        {
          :ems_ref         => "vm_ems_ref_3",
          :name            => "vm_name_3",
          :location        => "vm_location_3",
          :uid_ems         => "vm_uid_ems_3",
          :vendor          => "amazon",
          :raw_power_state => "unknown",
        }
      ],
      :extra_hardware => [
        {
          :vm_or_template_id   => @vm3.id,
          :bitness             => 64,
          :virtualization_type => "virtualization_type_3",
          :guest_os            => nil,
        }
      ],
      :extra_disks    => [
        {
          :hardware_id => @vm3.hardware.id,
          :device_name => "disk_name_3",
          :device_type => "disk",
        }, {
          :hardware_id => @vm3.hardware.id,
          :device_name => "disk_name_31",
          :device_type => "disk",
        }
      ]
    )
  end

  it "do a targeted refresh that will create/update vm, then create/update/delete Vm's hardware and disks" do
    # Get the relations
    initialize_all_inventory_collections
    initialize_inventory_collection_data

    # Invoke the InventoryCollections saving
    InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

    # Assert all data were filled
    load_records
    assert_everything_is_collected

    ### Second refresh ###
    # Initialize the InventoryCollections and data for a new VM
    initialize_inventory_collections(%i[vms hardwares])

    @vm_data_3 = vm_data(3).merge(
      :key_pairs => [@persister.key_pairs.lazy_find(key_pair_data(2)[:name])]
    )
    @hardware_data_3 = hardware_data(3).merge(
      :guest_os       => @persister.hardwares.lazy_find(@persister.miq_templates.lazy_find(image_data(2)[:ems_ref]), :key => :guest_os),
      :vm_or_template => @persister.vms.lazy_find(vm_data(3)[:ems_ref])
    )

    # Fill InventoryCollections with data
    {
      :vms       => [@vm_data_3],
      :hardwares => [@hardware_data_3],
    }.each_pair do |inventory_collection_name, data_arr|
      data_arr.each do |data|
        @persister.send(inventory_collection_name).build(data)
      end
    end

    # Invoke the InventoryCollections saving
    InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

    ### Third refresh ###
    # Initialize the InventoryCollections and data for the disks with new disk under a vm

    @vm3 = Vm.find_by(:ems_ref => "vm_ems_ref_3")

    initialize_inventory_collections(%i[disks])

    @persister.add_collection(:disks) do |builder|
      builder.add_properties(
        :parent                       => @vm3,
        :manager_ref                  => %i[hardware device_name],
        :parent_inventory_collections => []
      )
    end

    @disk_data_3 = disk_data(3).merge(
      :hardware => @persister.hardwares.lazy_find(@persister.vms.lazy_find(vm_data(3)[:ems_ref]))
    )
    @disk_data_31 = disk_data(31).merge(
      :hardware => @persister.hardwares.lazy_find(@persister.vms.lazy_find(vm_data(3)[:ems_ref]))
    )

    @persister.disks.build(@disk_data_3)
    @persister.disks.build(@disk_data_31)

    # Invoke the InventoryCollections saving
    InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

    # Assert all data were filled
    load_records
    @vm3          = Vm.find_by(:ems_ref => "vm_ems_ref_3")
    @vm_hardware3 = Hardware.find_by(:vm_or_template => @vm3)
    @disk3        = Disk.find_by(:hardware => @vm_hardware3, :device_name => "disk_name_3")
    @disk31       = Disk.find_by(:hardware => @vm_hardware3, :device_name => "disk_name_31")

    expect(@vm3.hardware.id).to eq(@vm_hardware3.id)
    expect(@vm3.hardware.disks.pluck(:id)).to match_array([@disk3.id, @disk31.id])
    expect(@vm3.key_pairs.pluck(:id)).to match_array([@key_pair2.id])

    assert_everything_is_collected(
      :extra_vms      => [
        {
          :ems_ref         => "vm_ems_ref_3",
          :name            => "vm_name_3",
          :location        => "vm_location_3",
          :uid_ems         => "vm_uid_ems_3",
          :vendor          => "amazon",
          :raw_power_state => "unknown",
        }
      ],
      :extra_hardware => [
        {
          :vm_or_template_id   => @vm3.id,
          :bitness             => 64,
          :virtualization_type => "virtualization_type_3",
          :guest_os            => nil,
        }
      ],
      :extra_disks    => [
        {
          :hardware_id => @vm3.hardware.id,
          :device_name => "disk_name_3",
          :device_type => "disk",
        }, {
          :hardware_id => @vm3.hardware.id,
          :device_name => "disk_name_31",
          :device_type => "disk",
        }
      ]
    )

    ### Fourth refresh ###
    # Add new disk and remove a disk under a vm

    @vm3 = Vm.find_by(:ems_ref => "vm_ems_ref_3")

    initialize_inventory_collections(%i[disks])
    @persister.add_collection(:disks) do |builder|
      builder.add_properties(:parent                       => @vm3,
                             :manager_ref                  => %i[hardware device_name],
                             :parent_inventory_collections => [])
    end
    @disk_data_3 = disk_data(3).merge(
      :hardware => @persister.hardwares.lazy_find(@persister.vms.lazy_find(vm_data(3)[:ems_ref]))
    )
    @disk_data_32 = disk_data(32).merge(
      :hardware => @persister.hardwares.lazy_find(@persister.vms.lazy_find(vm_data(3)[:ems_ref]))
    )

    @persister.disks.build(@disk_data_3)
    @persister.disks.build(@disk_data_32)

    # Invoke the InventoryCollections saving
    InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

    # Assert all data were filled
    load_records
    @vm3          = Vm.find_by(:ems_ref => "vm_ems_ref_3")
    @vm_hardware3 = Hardware.find_by(:vm_or_template => @vm3)
    @disk3        = Disk.find_by(:hardware => @vm_hardware3, :device_name => "disk_name_3")
    @disk32       = Disk.find_by(:hardware => @vm_hardware3, :device_name => "disk_name_32")

    expect(@vm3.hardware.id).to eq(@vm_hardware3.id)
    expect(@vm3.hardware.disks.pluck(:id)).to match_array([@disk3.id, @disk32.id])
    expect(@vm3.key_pairs.pluck(:id)).to match_array([@key_pair2.id])

    assert_everything_is_collected(
      :extra_vms      => [
        {
          :ems_ref         => "vm_ems_ref_3",
          :name            => "vm_name_3",
          :location        => "vm_location_3",
          :uid_ems         => "vm_uid_ems_3",
          :vendor          => "amazon",
          :raw_power_state => "unknown",
        }
      ],
      :extra_hardware => [
        {
          :vm_or_template_id   => @vm3.id,
          :bitness             => 64,
          :virtualization_type => "virtualization_type_3",
          :guest_os            => nil,
        }
      ],
      :extra_disks    => [
        {
          :hardware_id => @vm3.hardware.id,
          :device_name => "disk_name_3",
          :device_type => "disk",
        }, {
          :hardware_id => @vm3.hardware.id,
          :device_name => "disk_name_32",
          :device_type => "disk",
        }
      ]
    )
  end

  it "do a targeted refresh that will create/update vm, then create/update/delete Vm's hardware and disks using arel" do
    # Get the relations
    initialize_all_inventory_collections
    initialize_inventory_collection_data

    # Invoke the InventoryCollections saving
    InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

    # Assert all data were filled
    load_records
    assert_everything_is_collected

    ### Second refresh ###
    # Do a targeted refresh for couple of VMs, hardwares and disks using arel comparison
    initialize_inventory_collections(%i[vms hardwares disks])

    vm_refs = %w[vm_ems_ref_3 vm_ems_ref_4]

    vms_init_data(
      :arel => @ems.vms.where(:ems_ref => vm_refs)
    )

    hardwares_init_data(
      :arel                         => @ems.hardwares.joins(:vm_or_template).where(:vms => {:ems_ref => vm_refs}),
      :strategy                     => :local_db_find_missing_references,
      :manager_ref                  => %i[vm_or_template],
      :parent_inventory_collections => %i[vms]
    )

    disks_init_data(
      :arel                         => @ems.disks.joins(:hardware => :vm_or_template).where('hardware' => {'vms' => {'ems_ref' => vm_refs}}),
      :parent_inventory_collections => %i[vms]
    )

    @vm_data_3 = vm_data(3).merge(
      :key_pairs             => [@persister.key_pairs.lazy_find(key_pair_data(2)[:name])],
      :ext_management_system => @ems
    )
    @hardware_data_3 = hardware_data(3).merge(
      :guest_os       => @persister.hardwares.lazy_find(@persister.miq_templates.lazy_find(image_data(2)[:ems_ref]), :key => :guest_os),
      :vm_or_template => @persister.vms.lazy_find(vm_data(3)[:ems_ref])
    )

    @disk_data_3 = disk_data(3).merge(
      :hardware => @persister.hardwares.lazy_find(@persister.vms.lazy_find(vm_data(3)[:ems_ref]))
    )
    @disk_data_31 = disk_data(31).merge(
      :hardware => @persister.hardwares.lazy_find(@persister.vms.lazy_find(vm_data(3)[:ems_ref]))
    )

    # Fill InventoryCollections with data
    {
      :vms       => [@vm_data_3],
      :hardwares => [@hardware_data_3],
      :disks     => [@disk_data_3, @disk_data_31],
    }.each_pair do |inventory_collection_name, data_arr|
      data_arr.each do |data|
        @persister.send(inventory_collection_name).build(data)
      end
    end

    # Invoke the InventoryCollections saving
    InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

    # Assert all data were filled
    load_records
    @vm3          = Vm.find_by(:ems_ref => "vm_ems_ref_3")
    @vm_hardware3 = Hardware.find_by(:vm_or_template => @vm3)
    @disk3        = Disk.find_by(:hardware => @vm_hardware3, :device_name => "disk_name_3")
    @disk31       = Disk.find_by(:hardware => @vm_hardware3, :device_name => "disk_name_31")

    expect(@vm3.hardware.id).to eq(@vm_hardware3.id)
    expect(@vm3.hardware.disks.pluck(:id)).to match_array([@disk3.id, @disk31.id])
    expect(@vm3.key_pairs.pluck(:id)).to match_array([@key_pair2.id])

    assert_everything_is_collected(
      :extra_vms      => [
        {
          :ems_ref         => "vm_ems_ref_3",
          :name            => "vm_name_3",
          :location        => "vm_location_3",
          :uid_ems         => "vm_uid_ems_3",
          :vendor          => "amazon",
          :raw_power_state => "unknown",
        }
      ],
      :extra_hardware => [
        {
          :vm_or_template_id   => @vm3.id,
          :bitness             => 64,
          :virtualization_type => "virtualization_type_3",
          :guest_os            => "linux_generic_2",
        }
      ],
      :extra_disks    => [
        {
          :hardware_id => @vm3.hardware.id,
          :device_name => "disk_name_3",
          :device_type => "disk",
        }, {
          :hardware_id => @vm3.hardware.id,
          :device_name => "disk_name_31",
          :device_type => "disk",
        }
      ]
    )

    ### Third refresh ###
    # Do a targeted refresh again with some new data and some data missing
    initialize_inventory_collections(%i[vms hardwares disks])

    vm_refs = %w[vm_ems_ref_3 vm_ems_ref_5]

    @persister.add_collection(:vms) do |builder|
      builder.add_properties(
        :association => nil,
        :arel        => @ems.vms.where(:ems_ref => vm_refs),
        :model_class => ManageIQ::Providers::CloudManager::Vm
      )
    end
    @persister.add_collection(:hardwares) do |builder|
      builder.add_properties(
        :association => nil,
        :arel        => @ems.hardwares.joins(:vm_or_template).where(:vms => {:ems_ref => vm_refs}),
        :manager_ref => %i[vm_or_template],
        :model_class => Hardware
      )
    end
    @persister.add_collection(:disks) do |builder|
      builder.add_properties(
        :association => nil,
        :model_class => Disk,
        :arel        => @ems.disks.joins(:hardware => :vm_or_template).where('hardware' => {'vms' => {'ems_ref' => vm_refs}}),
        :manager_ref => %i[hardware device_name]
      )
    end
    @persister.add_collection(:image_hardwares) do |builder|
      builder.add_properties(
        :association => nil,
        :arel        => @ems.hardwares,
        :manager_ref => %i[vm_or_template],
        :model_class => Hardware,
        :name        => :image_hardwares,
        :strategy    => :local_db_cache_all
      )
    end

    @vm_data_3 = vm_data(3).merge(
      :key_pairs             => [@persister.key_pairs.lazy_find(key_pair_data(2)[:name])],
      :ext_management_system => @ems
    )
    @vm_data_5 = vm_data(5).merge(
      :key_pairs             => [@persister.key_pairs.lazy_find(key_pair_data(2)[:name])],
      :ext_management_system => @ems
    )
    @hardware_data_5 = hardware_data(5).merge(
      :guest_os       => @persister.image_hardwares.lazy_find(@persister.miq_templates.lazy_find(image_data(2)[:ems_ref]), :key => :guest_os),
      :vm_or_template => @persister.vms.lazy_find(vm_data(5)[:ems_ref])
    )
    @disk_data_5 = disk_data(5).merge(
      :hardware => @persister.hardwares.lazy_find(@persister.vms.lazy_find(vm_data(5)[:ems_ref]))
    )

    # Fill InventoryCollections with data
    {
      :vms       => [@vm_data_3, @vm_data_5],
      :hardwares => [@hardware_data_5],
      :disks     => [@disk_data_5],
    }.each_pair do |inventory_collection_name, data_arr|
      data_arr.each do |data|
        @persister.send(inventory_collection_name).build(data)
      end
    end

    # Invoke the InventoryCollections saving
    InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

    # Assert all data were filled
    load_records
    @vm3          = Vm.find_by(:ems_ref => "vm_ems_ref_3")
    @vm5          = Vm.find_by(:ems_ref => "vm_ems_ref_5")
    @vm_hardware5 = Hardware.find_by(:vm_or_template => @vm5)
    @disk5        = Disk.find_by(:hardware => @vm_hardware5, :device_name => "disk_name_5")

    expect(@vm3.key_pairs.pluck(:id)).to match_array([@key_pair2.id])

    expect(@vm5.hardware.id).to eq(@vm_hardware5.id)
    expect(@vm5.hardware.disks.pluck(:id)).to match_array([@disk5.id])
    expect(@vm5.key_pairs.pluck(:id)).to match_array([@key_pair2.id])

    assert_everything_is_collected(
      :extra_vms      => [
        {
          :ems_ref         => "vm_ems_ref_3",
          :name            => "vm_name_3",
          :location        => "vm_location_3",
          :uid_ems         => "vm_uid_ems_3",
          :vendor          => "amazon",
          :raw_power_state => "unknown",
        }, {
          :ems_ref         => "vm_ems_ref_5",
          :name            => "vm_name_5",
          :location        => "vm_location_5",
          :uid_ems         => "vm_uid_ems_5",
          :vendor          => "amazon",
          :raw_power_state => "unknown",
        }
      ],
      :extra_hardware => [
        {
          :vm_or_template_id   => @vm5.id,
          :bitness             => 64,
          :virtualization_type => "virtualization_type_5",
          :guest_os            => "linux_generic_2",
        }
      ],
      :extra_disks    => [
        {
          :hardware_id => @vm5.hardware.id,
          :device_name => "disk_name_5",
          :device_type => "disk",
        }
      ]
    )
  end

  def load_records
    @orchestration_stack_0_1  = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_0_1")
    @orchestration_stack_1_11 = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_1_11")
    @orchestration_stack_1_12 = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_1_12")

    @orchestration_stack_resource_1_11 = OrchestrationStackResource.find_by(:ems_ref => "stack_ems_ref_1_11")
    @orchestration_stack_resource_1_12 = OrchestrationStackResource.find_by(:ems_ref => "stack_ems_ref_1_12")

    @vm1 = Vm.find_by(:ems_ref => "vm_ems_ref_1")
    @vm2 = Vm.find_by(:ems_ref => "vm_ems_ref_2")

    @miq_template1 = MiqTemplate.find_by(:ems_ref => "image_ems_ref_1")
    @miq_template2 = MiqTemplate.find_by(:ems_ref => "image_ems_ref_2")

    @hardware1 = Hardware.find_by(:vm_or_template => @vm1)
    @hardware2 = Hardware.find_by(:vm_or_template => @vm2)
    @hardware3 = Hardware.find_by(:vm_or_template => @miq_template1)
    @hardware4 = Hardware.find_by(:vm_or_template => @miq_template2)

    @key_pair1  = ManageIQ::Providers::CloudManager::AuthKeyPair.find_by(:name => "key_pair_name_1")
    @key_pair2  = ManageIQ::Providers::CloudManager::AuthKeyPair.find_by(:name => "key_pair_name_2")
    @key_pair21 = ManageIQ::Providers::CloudManager::AuthKeyPair.find_by(:name => "key_pair_name_21")

    @disk1  = Disk.find_by(:hardware => @hardware1, :device_name => "disk_name_1")
    @disk12 = Disk.find_by(:hardware => @hardware1, :device_name => "disk_name_12")
    @disk13 = Disk.find_by(:hardware => @hardware1, :device_name => "disk_name_13")
    @disk2  = Disk.find_by(:hardware => @hardware2, :device_name => "disk_name_2")
  end

  def assert_relations
    expect(@orchestration_stack_0_1.resources).to match_array([@orchestration_stack_resource_1_11,
                                                               @orchestration_stack_resource_1_12])
    expect(@orchestration_stack_1_11.resources).to match_array(nil)
    expect(@orchestration_stack_1_12.resources).to match_array(nil)

    expect(@orchestration_stack_resource_1_11.stack).to eq(@orchestration_stack_0_1)
    expect(@orchestration_stack_resource_1_12.stack).to eq(@orchestration_stack_0_1)

    expect(@orchestration_stack_0_1.parent).to eq(nil)
    expect(@orchestration_stack_1_11.parent).to eq(@orchestration_stack_0_1)
    expect(@orchestration_stack_1_12.parent).to eq(@orchestration_stack_0_1)

    expect(@vm1.hardware.id).to eq(@hardware1.id)
    expect(@vm2.hardware.id).to eq(@hardware2.id)
    expect(@miq_template1.hardware.id).to eq(@hardware3.id)
    expect(@miq_template2.hardware.id).to eq(@hardware4.id)

    expect(@vm1.hardware.disks.pluck(:id)).to match_array([@disk1.id, @disk12.id, @disk13.id])
    expect(@vm2.hardware.disks.pluck(:id)).to match_array([@disk2.id])

    expect(@vm1.key_pairs.pluck(:id)).to match_array([@key_pair1.id])
    expect(@vm2.key_pairs.pluck(:id)).to match_array([@key_pair2.id, @key_pair21.id])
  end

  def assert_everything_is_collected(extra_vms: [], extra_hardware: [], extra_disks: [])
    @ems.reload
    assert_relations

    assert_all_records_match_hashes(
      [OrchestrationStack.all, @ems.orchestration_stacks],
      {
        :ems_ref       => "stack_ems_ref_0_1",
        :name          => "stack_name_0_1",
        :description   => "stack_description_0_1",
        :status        => "stack_status_0_1",
        :status_reason => "stack_status_reason_0_1",
      }, {
        :ems_ref       => "stack_ems_ref_1_11",
        :name          => "stack_name_1_11",
        :description   => "stack_description_1_11",
        :status        => "stack_status_1_11",
        :status_reason => "stack_status_reason_1_11",
      }, {
        :ems_ref       => "stack_ems_ref_1_12",
        :name          => "stack_name_1_12",
        :description   => "stack_description_1_12",
        :status        => "stack_status_1_12",
        :status_reason => "stack_status_reason_1_12",
      }
    )

    assert_all_records_match_hashes(
      [OrchestrationStackResource.all, @ems.orchestration_stacks_resources],
      {
        :ems_ref           => "stack_ems_ref_1_11",
        :name              => "stack_resource_name_1_11",
        :logical_resource  => "stack_resource_logical_resource_1_11",
        :physical_resource => "stack_resource_physical_resource_1_11",
      }, {
        :ems_ref           => "stack_ems_ref_1_12",
        :name              => "stack_resource_name_1_12",
        :logical_resource  => "stack_resource_logical_resource_1_12",
        :physical_resource => "stack_resource_physical_resource_1_12",
      }
    )

    vms = [
      {
        :ems_ref         => "vm_ems_ref_1",
        :name            => "vm_name_1",
        :location        => "vm_location_1",
        :uid_ems         => "vm_uid_ems_1",
        :vendor          => "amazon",
        :raw_power_state => "unknown",
      }, {
        :ems_ref         => "vm_ems_ref_2",
        :name            => "vm_name_2",
        :location        => "vm_location_2",
        :uid_ems         => "vm_uid_ems_2",
        :vendor          => "amazon",
        :raw_power_state => "unknown",
      }
    ]
    vms += extra_vms

    assert_all_records_match_hashes([Vm.all, @ems.vms], *vms)

    hardware = [
      {
        :vm_or_template_id   => @vm1.id,
        :bitness             => 64,
        :virtualization_type => "virtualization_type_1",
        :guest_os            => "linux_generic_1",
      }, {
        :vm_or_template_id   => @vm2.id,
        :bitness             => 64,
        :virtualization_type => "virtualization_type_2",
        :guest_os            => "linux_generic_2",
      }, {
        :vm_or_template_id   => @miq_template1.id,
        :bitness             => nil,
        :virtualization_type => nil,
        :guest_os            => "linux_generic_1",
      }, {
        :vm_or_template_id   => @miq_template2.id,
        :bitness             => nil,
        :virtualization_type => nil,
        :guest_os            => "linux_generic_2",
      }
    ]
    hardware += extra_hardware

    assert_all_records_match_hashes([Hardware.all, @ems.hardwares], *hardware)

    disks = [
      {
        :hardware_id => @vm1.hardware.id,
        :device_name => "disk_name_1",
        :device_type => "disk",
      }, {
        :hardware_id => @vm1.hardware.id,
        :device_name => "disk_name_12",
        :device_type => "disk",
      }, {
        :hardware_id => @vm1.hardware.id,
        :device_name => "disk_name_13",
        :device_type => "disk",
      }, {
        :hardware_id => @vm2.hardware.id,
        :device_name => "disk_name_2",
        :device_type => "disk",
      }
    ]
    disks += extra_disks

    assert_all_records_match_hashes([Disk.all, @ems.disks], *disks)

    assert_all_records_match_hashes(
      [ManageIQ::Providers::CloudManager::AuthKeyPair.all, @ems.key_pairs],
      {
        :name => "key_pair_name_1",
      }, {
        :name => "key_pair_name_2",
      }, {
        :name => "key_pair_name_21",
      }
    )
  end

  def all_collections
    %i[orchestration_stacks orchestration_stacks_resources vms miq_templates key_pairs hardwares disks]
  end

  def initialize_inventory_collection_data
    # Initialize the InventoryCollections data
    @orchestration_stack_data_0_1 = orchestration_stack_data("0_1").merge(
      # TODO(lsmola) not possible until we have an enhanced transitive edges check
      # :parent => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("0_0")[:ems_ref]))
      :parent => nil
    )
    @orchestration_stack_data_1_11 = orchestration_stack_data("1_11").merge(
      :parent => @persister.orchestration_stacks_resources.lazy_find(orchestration_stack_data("1_11")[:ems_ref],
                                                                     :key => :stack)
    )
    @orchestration_stack_data_1_12 = orchestration_stack_data("1_12").merge(
      :parent => @persister.orchestration_stacks_resources.lazy_find(orchestration_stack_data("1_12")[:ems_ref],
                                                                     :key => :stack)
    )
    @orchestration_stack_resource_data_1_11 = orchestration_stack_resource_data("1_11").merge(
      :ems_ref => orchestration_stack_data("1_11")[:ems_ref],
      :stack   => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("0_1")[:ems_ref])
    )
    @orchestration_stack_resource_data_1_12 = orchestration_stack_resource_data("1_12").merge(
      :ems_ref => orchestration_stack_data("1_12")[:ems_ref],
      :stack   => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("0_1")[:ems_ref])
    )

    @key_pair_data_1  = key_pair_data(1)
    @key_pair_data_2  = key_pair_data(2)
    @key_pair_data_21 = key_pair_data(21)

    @image_data_1 = image_data(1)
    @image_data_2 = image_data(2)

    @image_hardware_data_1 = image_hardware_data(1).merge(
      :vm_or_template => @persister.miq_templates.lazy_find(image_data(1)[:ems_ref])
    )
    @image_hardware_data_2 = image_hardware_data(2).merge(
      :vm_or_template => @persister.miq_templates.lazy_find(image_data(2)[:ems_ref])
    )

    @vm_data_1 = vm_data(1).merge(
      :key_pairs => [@persister.key_pairs.lazy_find(key_pair_data(1)[:name])]
    )
    @vm_data_2 = vm_data(2).merge(
      :key_pairs => [@persister.key_pairs.lazy_find(key_pair_data(2)[:name]),
                     @persister.key_pairs.lazy_find(key_pair_data(21)[:name])]
    )

    @hardware_data_1 = hardware_data(1).merge(
      :guest_os       => @persister.hardwares.lazy_find(@persister.miq_templates.lazy_find(image_data(1)[:ems_ref]), :key => :guest_os),
      :vm_or_template => @persister.vms.lazy_find(vm_data(1)[:ems_ref])
    )
    @hardware_data_2 = hardware_data(2).merge(
      :guest_os       => @persister.hardwares.lazy_find(@persister.miq_templates.lazy_find(image_data(2)[:ems_ref]), :key => :guest_os),
      :vm_or_template => @persister.vms.lazy_find(vm_data(2)[:ems_ref])
    )

    @disk_data_1 = disk_data(1).merge(
      :hardware => @persister.hardwares.lazy_find(@persister.vms.lazy_find(vm_data(1)[:ems_ref]))
    )
    @disk_data_12 = disk_data(12).merge(
      :hardware => @persister.hardwares.lazy_find(@persister.vms.lazy_find(vm_data(1)[:ems_ref]))
    )
    @disk_data_13 = disk_data(13).merge(
      :hardware => @persister.hardwares.lazy_find(@persister.vms.lazy_find(vm_data(1)[:ems_ref]))
    )
    @disk_data_2 = disk_data(2).merge(
      :hardware => @persister.hardwares.lazy_find(@persister.vms.lazy_find(vm_data(2)[:ems_ref]))
    )

    # Fill InventoryCollections with data
    {
      :orchestration_stacks           => [@orchestration_stack_data_0_1,
                                          @orchestration_stack_data_1_11,
                                          @orchestration_stack_data_1_12],
      :orchestration_stacks_resources => [@orchestration_stack_resource_data_1_11,
                                          @orchestration_stack_resource_data_1_12],
      :vms                            => [@vm_data_1,
                                          @vm_data_2],
      :miq_templates                  => [@image_data_1,
                                          @image_data_2],
      :hardwares                      => [@hardware_data_1,
                                          @hardware_data_2,
                                          @image_hardware_data_1,
                                          @image_hardware_data_2],
      :key_pairs                      => [@key_pair_data_1, @key_pair_data_2, @key_pair_data_21],
      :disks                          => [@disk_data_1, @disk_data_12, @disk_data_13, @disk_data_2],
    }.each_pair do |inventory_collection_name, data_arr|
      data_arr.each do |data|
        @persister.send(inventory_collection_name).build(data)
      end
    end
  end
end
