require_relative 'spec_helper'
require_relative '../helpers/spec_parsed_data'
require_relative '../helpers/spec_mocked_data'
require_relative '../helpers/test_persister'

describe InventoryRefresh::SaveInventory do
  include SpecHelper
  include SpecParsedData
  include SpecMockedData

  ######################################################################################################################
  #
  # Testing SaveInventory for directed acyclic graph (DAG) of the InventoryCollection dependencies, testing that
  # relations are saved correctly for a testing set of InventoryCollections whose dependencies look like:
  #
  #                                    +--------------+
  #                                    |              |
  #                                    |      VM      <------------+
  #                                 +-->              |            |
  #                                 +-------^------+            |
  #                                 |          |                   |
  #                                 |          |                   |
  #               +--------------+  |  +-------+------+     +------+-------+
  #               |              |  |  |              |     |              |
  #               |   Flavor     +--+  |   Hardware   +----->  MiqTemplate |
  #               |              |     |              |     |              |
  #               +--------------+     +----^---^-----+     +--------------+
  #                                         |   |
  #                                +--------+   +-------+
  #                                |                    |
  #                         +------+-------+     +------+-------+
  #                         |              |     |              |
  #                         |     Disk     |     |    Network   |
  #                         |              |     |              |
  #                         +--------------+     +--------------+
  #
  # The +--> marks a dependency, so Hardware +---> Vm means Hardware depends on Vm. So in this case, we need to make
  # sure Vm is saved to DB before Hardware does, since Hardware references Vm records
  #
  # The dependency of the InventoryCollection is caused byt find or by lazy_find called on InventoryCollection.
  #
  # Explanation of the lazy_find vs find:
  #
  # If we do lazy_find, it means InventoryCollection can be empty at that time and this lazy_find is evaluated right
  # before the InventoryCollections is saved. That means it doesn't depend on order how the InventoryCollections are
  # filled with data. If we use find, the InventoryCollection already needs to be filled with data, otherwise the find
  # results with nil.
  #
  # Example of the dependency:
  #   the data of the InventoryCollection for Hardware contains
  #
  #   @persister.vms.lazy_find(instance.id) or @persister.vms.find(instance.id)
  #
  #   This code results in LazyInventoryObject or InventoryObject object, which we need to translate into Vm record,
  #   when we save Hardware record. Therefore, this depends on Vm being already saved in the DB,
  #
  # Example of the dependency using :key:
  #
  #   Using @persister.hardwares.lazy_find(instance.image_id, :key => :guest_os) we do not create a dependency, this code
  #   fetches an attribute :guest_os of the Hardware InventoryObject, we do not create a dependency. The attribute is
  #   available before we save the Hardware InventoryCollection.
  #
  #   But using @persister.hardwares.lazy_find(instance.image_id, :key => :vm_or_template), the attribute we are fetching
  #   is a record itself, that means we depend on the Hardware InventoryCollection being saved.
  #
  ######################################################################################################################
  #
  let(:persister_class) { ::TestPersister }

  before do
    @ems = FactoryBot.create(:ems_cloud)

    allow(@ems.class).to receive(:ems_type).and_return(:mock)
    @persister = persister_class.new(@ems, InventoryRefresh::TargetCollection.new(:manager => @ems))
  end

  context 'with empty DB' do
    before do
      initialize_data_and_inventory_collections
    end

    it 'creates a graph of InventoryCollections' do
      # Fill the InventoryCollections with data
      {
        :vms           => [@vm_data_1, @vm_data_12, @vm_data_2, @vm_data_4],
        :miq_templates => [@image_data_1, @image_data_2, @image_data_3],
        :hardwares     => [@hardware_data_1, @hardware_data_2, @hardware_data_12],
        :disks         => [@disk_data_1, @disk_data_12, @disk_data_13, @disk_data_2],
        :networks      => [@public_network_data_1, @public_network_data_12,
                           @public_network_data_13, @public_network_data_14, @public_network_data_2],
        :flavors       => [@flavor_data_1, @flavor_data_2, @flavor_data_3]
      }.each_pair do |inventory_collection_name, data_arr|
        data_arr.each do |data|
          @persister.send(inventory_collection_name).build(data)
        end
      end

      # Invoke the InventoryCollections saving
      InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

      # Assert saved data
      assert_full_inventory_collections_graph

      assert_all_records_match_hashes(
        [Vm.all, @ems.vms],
        {
          :ems_ref  => "vm_ems_ref_1",
          :name     => "vm_name_1",
          :location => "host_10_10_10_1.com",
        }, {
          :ems_ref  => "vm_ems_ref_12",
          :name     => "vm_name_12",
          :location => "host_10_10_10_1.com",
        }, {
          :ems_ref  => "vm_ems_ref_2",
          :name     => "vm_name_2",
          :location => "host_10_10_10_2.com",
        }, {
          :ems_ref  => "vm_ems_ref_4",
          :name     => "vm_name_4",
          :location => "default_value_unknown",
        }
      )
    end

    it 'creates and updates a graph of InventoryCollections' do
      # Fill the InventoryCollections with data
      {
        :vms           => [@vm_data_1, @vm_data_12, @vm_data_2, @vm_data_4],
        :miq_templates => [@image_data_1, @image_data_2, @image_data_3],
        :hardwares     => [@hardware_data_1, @hardware_data_2, @hardware_data_12],
        :disks         => [@disk_data_1, @disk_data_12, @disk_data_13, @disk_data_2],
        :networks      => [@public_network_data_1, @public_network_data_12,
                           @public_network_data_13, @public_network_data_14, @public_network_data_2],
        :flavors       => [@flavor_data_1, @flavor_data_2, @flavor_data_3],
      }.each_pair do |inventory_collection_name, data_arr|
        data_arr.each do |data|
          @persister.send(inventory_collection_name).build(data)
        end
      end

      # Invoke the InventoryCollections saving
      InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

      # Assert that saved data have the updated values, checking id to make sure the original records are updated
      assert_full_inventory_collections_graph

      assert_all_records_match_hashes(
        [Vm.all, @ems.vms],
        {
          :ems_ref  => "vm_ems_ref_1",
          :name     => "vm_name_1",
          :location => "host_10_10_10_1.com",
        }, {
          :ems_ref  => "vm_ems_ref_12",
          :name     => "vm_name_12",
          :location => "host_10_10_10_1.com",
        }, {
          :ems_ref  => "vm_ems_ref_2",
          :name     => "vm_name_2",
          :location => "host_10_10_10_2.com",
        }, {
          :ems_ref  => "vm_ems_ref_4",
          :name     => "vm_name_4",
          :location => "default_value_unknown",
        }
      )

      # Fetch the created Vms from the DB, for comparing after second refresh
      vm1  = Vm.find_by(:ems_ref => "vm_ems_ref_1")
      vm12 = Vm.find_by(:ems_ref => "vm_ems_ref_12")
      vm2  = Vm.find_by(:ems_ref => "vm_ems_ref_2")
      vm4  = Vm.find_by(:ems_ref => "vm_ems_ref_4")

      # Second saving with the updated data
      # Fill the InventoryCollections with data, that have a modified name
      initialize_data_and_inventory_collections
      {
        :vms           => [@vm_data_1.merge(:name => "vm_name_1_changed"),
                           @vm_data_12.merge(:name => "vm_name_12_changed"),
                           @vm_data_2.merge(:name => "vm_name_2_changed"),
                           @vm_data_4.merge(:name => "vm_name_4_changed"),
                           vm_data(5)],
        :miq_templates => [@image_data_1, @image_data_2, @image_data_3],
        :hardwares     => [@hardware_data_1, @hardware_data_2, @hardware_data_12],
        :disks         => [@disk_data_1, @disk_data_12, @disk_data_13, @disk_data_2],
        :networks      => [@public_network_data_1, @public_network_data_12,
                           @public_network_data_13, @public_network_data_14, @public_network_data_2],
        :flavors       => [@flavor_data_1, @flavor_data_2, @flavor_data_3],
      }.each_pair do |inventory_collection_name, data_arr|
        data_arr.each do |data|
          @persister.send(inventory_collection_name).build(data)
        end
      end

      # Invoke the InventoryCollections saving
      InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

      # Assert saved data
      assert_full_inventory_collections_graph
      # Assert that saved data have the updated values, checking id to make sure the original records are updated
      assert_all_records_match_hashes(
        [Vm.all, @ems.vms],
        {
          :id       => vm1.id,
          :ems_ref  => "vm_ems_ref_1",
          :name     => "vm_name_1_changed",
          :location => "host_10_10_10_1.com",
        }, {
          :id       => vm12.id,
          :ems_ref  => "vm_ems_ref_12",
          :name     => "vm_name_12_changed",
          :location => "host_10_10_10_1.com",
        }, {
          :id       => vm2.id,
          :ems_ref  => "vm_ems_ref_2",
          :name     => "vm_name_2_changed",
          :location => "host_10_10_10_2.com",
        }, {
          :id       => vm4.id,
          :ems_ref  => "vm_ems_ref_4",
          :name     => "vm_name_4_changed",
          :location => "default_value_unknown",
        }, {
          :id       => anything,
          :ems_ref  => "vm_ems_ref_5",
          :name     => "vm_name_5",
          :location => "vm_location_5",
        }
      )
    end
  end

  context 'with the existing data in the DB' do
    it 'updates existing records with a graph of InventoryCollections' do
      # Fill the mocked data in the DB
      initialize_mocked_records

      assert_all_records_match_hashes(
        [Vm.all, @ems.vms],
        {
          :ems_ref  => "vm_ems_ref_1",
          :name     => "vm_name_1",
          :location => "host_10_10_10_1.com",
        }, {
          :ems_ref  => "vm_ems_ref_12",
          :name     => "vm_name_12",
          :location => "host_10_10_10_1.com",
        }, {
          :ems_ref  => "vm_ems_ref_2",
          :name     => "vm_name_2",
          :location => "host_10_10_10_2.com",
        }, {
          :ems_ref  => "vm_ems_ref_4",
          :name     => "vm_name_4",
          :location => "default_value_unknown",
        }
      )

      # Now save the records using InventoryCollections
      # Fill the InventoryCollections with data, that have a modified name
      initialize_data_and_inventory_collections
      {
        :vms           => [@vm_data_1.merge(:name => "vm_name_1_changed"),
                           @vm_data_12.merge(:name => "vm_name_12_changed"),
                           @vm_data_2.merge(:name => "vm_name_2_changed"),
                           @vm_data_4.merge(:name => "vm_name_4_changed"),
                           vm_data(5)],
        :miq_templates => [@image_data_1, @image_data_2, @image_data_3],
        :hardwares     => [@hardware_data_1, @hardware_data_2, @hardware_data_12],
        :disks         => [@disk_data_1.merge(:device_type => "nvme_ssd_1"),
                           @disk_data_12.merge(:device_type => "nvme_ssd_12"),
                           @disk_data_13.merge(:device_type => "nvme_ssd_13"),
                           @disk_data_2.merge(:device_type => "nvme_ssd_2")],
        :networks      => [@public_network_data_1, @public_network_data_12,
                           @public_network_data_13, @public_network_data_14, @public_network_data_2],
        :flavors       => [@flavor_data_1, @flavor_data_2, @flavor_data_3],
      }.each_pair do |inventory_collection_name, data_arr|
        data_arr.each do |data|
          @persister.send(inventory_collection_name).build(data)
        end
      end

      # Invoke the InventoryCollections saving
      InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

      # Assert saved data
      assert_full_inventory_collections_graph
      # Assert that saved data have the updated values, checking id to make sure the original records are updated
      assert_all_records_match_hashes(
        [Vm.all, @ems.vms],
        {
          :id       => @vm1.id,
          :ems_ref  => "vm_ems_ref_1",
          :name     => "vm_name_1_changed",
          :location => "host_10_10_10_1.com",
        }, {
          :id       => @vm12.id,
          :ems_ref  => "vm_ems_ref_12",
          :name     => "vm_name_12_changed",
          :location => "host_10_10_10_1.com",
        }, {
          :id       => @vm2.id,
          :ems_ref  => "vm_ems_ref_2",
          :name     => "vm_name_2_changed",
          :location => "host_10_10_10_2.com",
        }, {
          :id       => @vm4.id,
          :ems_ref  => "vm_ems_ref_4",
          :name     => "vm_name_4_changed",
          :location => "default_value_unknown",
        }, {
          :id       => anything,
          :ems_ref  => "vm_ems_ref_5",
          :name     => "vm_name_5",
          :location => "vm_location_5",
        }
      )

      assert_all_records_match_hashes(
        [Disk.all, @ems.disks],
        {
          :id          => @disk1.id,
          :hardware    => @hardware1,
          :device_type => "nvme_ssd_1"
        }, {
          :id          => @disk12.id,
          :hardware    => @hardware12,
          :device_type => "nvme_ssd_12"
        }, {
          :id          => @disk13.id,
          :hardware    => @hardware12,
          :device_type => "nvme_ssd_13"
        }, {
          :id          => @disk2.id,
          :hardware    => @hardware2,
          :device_type => "nvme_ssd_2"
        }
      )

      vm1  = Vm.find_by(:ems_ref => "vm_ems_ref_1")
      vm12 = Vm.find_by(:ems_ref => "vm_ems_ref_12")
      vm2  = Vm.find_by(:ems_ref => "vm_ems_ref_2")

      # Check that all records were only updated
      expect(vm1.hardware.id).to eq(@hardware1.id)
      expect(vm12.hardware.id).to eq(@hardware12.id)
      expect(vm2.hardware.id).to eq(@hardware2.id)
      expect(vm1.hardware.networks.pluck(:id)).to match_array([@public_network1.id])
      expect(vm12.hardware.networks.pluck(:id)).to match_array([@public_network12.id, @public_network13.id])
      expect(vm2.hardware.networks.pluck(:id)).to match_array([@public_network2.id])
      expect(vm1.hardware.disks.pluck(:id)).to match_array([@disk1.id])
      expect(vm12.hardware.disks.pluck(:id)).to match_array([@disk12.id, @disk13.id])
      expect(vm2.hardware.disks.pluck(:id)).to match_array([@disk2.id])
      expect(vm1.flavor.id).to eq(@flavor1.id)
      expect(vm12.flavor.id).to eq(@flavor1.id)
      expect(vm2.flavor.id).to eq(@flavor2.id)
    end

    it "db unique indexes prevent duplicates from being created" do
      initialize_mocked_records

      expect do
        FactoryBot.create(
          :vm_cloud,
          vm_data(1).merge(
            :flavor                => @flavor_1,
            :location              => 'host_10_10_10_1.com',
            :ext_management_system => @ems,
          )
        )
      end.to(
        raise_error(/duplicate key value violates unique constraint "index_vms_on_ems_id_and_ems_ref"/)
      )
    end
  end

  context "lazy_find vs find" do
    before do
      # Initialize the InventoryCollections
      @persister.add_collection(:vms) do |builder|
        builder.add_properties(:model_class => ManageIQ::Providers::CloudManager::Vm)
      end
      @persister.add_collection(:hardwares) do |builder|
        builder.add_properties(
          :manager_ref                  => %i(vm_or_template),
          :parent_inventory_collections => %i(vms)
        )
      end
    end

    it "misses relation using find and loading data in a wrong order" do
      # Load data into InventoryCollections in wrong order, we are accessing @data[:vms] using find before we filled
      # it with data
      @vm_data_1 = vm_data(1)
      @hardware_data_1 = hardware_data(1).merge(
        :vm_or_template => @persister.vms.find(vm_data(1)[:ems_ref])
      )
      {
        :vms       => [@vm_data_1],
        :hardwares => [@hardware_data_1],
      }.each_pair do |inventory_collection_name, data_arr|
        data_arr.each do |data|
          @persister.send(inventory_collection_name).build(data)
        end
      end

      # Invoke the InventoryCollections saving
      InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

      # Assert saved data
      hardware1 = Hardware.find_by(:virtualization_type => "virtualization_type_1")
      expect(hardware1).to eq(nil)
    end

    it "has a relation using find and loading data in a right order" do
      # Load data into InventoryCollections in a right order, we are accessing @data[:vms] using find when the data
      # are present
      @vm_data_1 = vm_data(1)
      @persister.vms.build(@vm_data_1)

      @hardware_data_1 = hardware_data(1).merge(
        :vm_or_template => @persister.vms.find(vm_data(1)[:ems_ref])
      )
      @persister.hardwares.build(@hardware_data_1)

      # Invoke the InventoryCollections saving
      InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

      # Assert saved data
      vm1 = Vm.find_by!(:ems_ref => "vm_ems_ref_1")
      hardware1 = Hardware.find_by!(:virtualization_type => "virtualization_type_1")
      expect(hardware1.vm_or_template).to eq(vm1)
    end

    it "has a relation using lazy_find and loading data in a wrong order" do
      # Using lazy_find, it doesn't matter in which order we load data into inventory_collections. The lazy relation
      # is evaluated before saving, all InventoryCollections have data loaded at that time.
      @vm_data_1 = vm_data(1)
      @hardware_data_1 = hardware_data(1).merge(
        :vm_or_template => @persister.vms.lazy_find(vm_data(1)[:ems_ref])
      )
      {
        :vms       => [@vm_data_1],
        :hardwares => [@hardware_data_1],
      }.each_pair do |inventory_collection_name, data_arr|
        data_arr.each do |data|
          @persister.send(inventory_collection_name).build(data)
        end
      end

      # Invoke the InventoryCollections saving
      InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

      # Assert saved data
      vm1 = Vm.find_by!(:ems_ref => "vm_ems_ref_1")
      hardware1 = Hardware.find_by!(:virtualization_type => "virtualization_type_1")
      expect(hardware1.vm_or_template).to eq(vm1)
    end
  end

  context "assert_referential_integrity" do
    before do
      # Initialize the InventoryCollections
      @persister.add_collection(:vms) do |builder|
        builder.add_properties(:model_class => ManageIQ::Providers::CloudManager::Vm)
      end
      @persister.add_collection(:hardwares) do |builder|
        builder.add_properties(
          :manager_ref                  => %i(vm_or_template virtualization_type),
          :parent_inventory_collections => %i(vms)
        )
      end

      @vm_data_1 = vm_data(1)
      @hardware_data_1 = hardware_data(1).merge(:vm_or_template => nil)

      {
        :vms       => [@vm_data_1],
        :hardwares => [@hardware_data_1],
      }.each_pair do |inventory_collection_name, data_arr|
        data_arr.each do |data|
          @persister.send(inventory_collection_name).build(data)
        end
      end
    end

    it "raises in test if field used in manager_ref nil" do
      expect { InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections) }.to raise_error(/referential integrity/i)
    end

    it "raises in developement if field used in manager_ref nil" do
      expect { InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections) }.to raise_error(/referential integrity/i)
    end
  end

  def assert_full_inventory_collections_graph
    vm1  = Vm.find_by(:ems_ref => "vm_ems_ref_1")
    vm12 = Vm.find_by(:ems_ref => "vm_ems_ref_12")
    vm2  = Vm.find_by(:ems_ref => "vm_ems_ref_2")
    vm4  = Vm.find_by(:ems_ref => "vm_ems_ref_4")

    expect(vm1.hardware.virtualization_type).to eq("virtualization_type_1")
    expect(vm1.hardware.disks.collect(&:device_name)).to match_array(["disk_name_1"])
    expect(vm1.hardware.networks.collect(&:ipaddress)).to match_array(["10.10.10.1"])

    expect(vm12.hardware.virtualization_type).to eq("virtualization_type_12")
    expect(vm12.hardware.disks.collect(&:device_name)).to match_array(%w(disk_name_12 disk_name_13))
    expect(vm12.hardware.networks.collect(&:ipaddress)).to match_array(["10.10.10.12", "10.10.10.13"])

    expect(vm2.hardware.virtualization_type).to eq("virtualization_type_2")
    expect(vm2.hardware.disks.collect(&:device_name)).to match_array(["disk_name_2"])
    expect(vm2.hardware.networks.collect(&:ipaddress)).to match_array(["10.10.10.2"])

    # skeletaly precreated hardware
    expect(vm4.hardware.virtualization_type).to eq(nil)
  end

  def initialize_data_and_inventory_collections
    # Initialize the InventoryCollections
    @persister.add_collection(:vms) do |builder|
      builder.add_properties(:model_class => ManageIQ::Providers::CloudManager::Vm)
    end
    @persister.add_collection(:miq_templates) do |builder|
      builder.add_properties(:model_class => ManageIQ::Providers::CloudManager::Template)
    end
    @persister.add_collection(:hardwares) do |builder|
      builder.add_properties(
        :manager_ref                  => %i(vm_or_template),
        :parent_inventory_collections => %i(vms miq_templates)
      )
    end
    @persister.add_collection(:disks) do |builder|
      builder.add_properties(
        :manager_ref                  => %i(hardware device_name),
        :parent_inventory_collections => %i(vms miq_templates)
      )
    end
    @persister.add_collection(:networks) do |builder|
      builder.add_properties(
        :manager_ref                  => %i(hardware description),
        :parent_inventory_collections => %i(vms miq_templates)
      )
    end
    @persister.add_collection(:flavors) do |builder|
      builder.add_properties(
        :model_class => ManageIQ::Providers::CloudManager::Flavor,
        :manager_ref => %i(name)
      )
    end

    # Get parsed data with the lazy_relations
    @flavor_data_1        = flavor_data(1)
    @flavor_data_2        = flavor_data(2)
    @flavor_data_3        = flavor_data(3)

    @image_data_1 = image_data(1)
    @image_data_2 = image_data(2)
    @image_data_3 = image_data(3)

    lazy_find_vm_1       = @persister.vms.lazy_find(:ems_ref => vm_data(1)[:ems_ref])
    lazy_find_hardware_1 = @persister.hardwares.lazy_find(:vm_or_template => lazy_find_vm_1)
    lazy_find_vm_2       = @persister.vms.lazy_find(:ems_ref => vm_data(2)[:ems_ref])
    lazy_find_hardware_2 = @persister.hardwares.lazy_find(:vm_or_template => lazy_find_vm_2)
    lazy_find_vm_4       = @persister.vms.lazy_find(:ems_ref => vm_data(4)[:ems_ref])
    lazy_find_hardware_4 = @persister.hardwares.lazy_find(:vm_or_template => lazy_find_vm_4)

    @vm_data_1 = vm_data(1).merge(
      :flavor    => @persister.flavors.lazy_find(flavor_data(1)[:name]),
      :location  => @persister.networks.lazy_find({:hardware => lazy_find_hardware_1, :description => "public"},
                                                  {:key     => :hostname,
                                                   :default => 'default_value_unknown'}),
    )

    @vm_data_12 = vm_data(12).merge(
      :flavor    => @persister.flavors.lazy_find(flavor_data(1)[:name]),
      :location  => @persister.networks.lazy_find({:hardware => lazy_find_hardware_1, :description => "public"},
                                                  {:key     => :hostname,
                                                   :default => 'default_value_unknown'}),
    )

    @vm_data_2 = vm_data(2).merge(
      :flavor    => @persister.flavors.lazy_find(flavor_data(2)[:name]),
      :location  => @persister.networks.lazy_find({:hardware => lazy_find_hardware_2, :description => "public"},
                                                  {:key     => :hostname,
                                                   :default => 'default_value_unknown'}),
    )

    @vm_data_4 = vm_data(4).merge(
      :flavor    => @persister.flavors.lazy_find(flavor_data(4)[:name]),
      :location  => @persister.networks.lazy_find({:hardware => lazy_find_hardware_4, :description => "public"},
                                                  {:key     => :hostname,
                                                   :default => 'default_value_unknown'}),
    )

    @hardware_data_1 = hardware_data(1).merge(
      :guest_os       => @persister.miq_templates.lazy_find(image_data(1)[:ems_ref], :key => :guest_os),
      :vm_or_template => @persister.vms.lazy_find(vm_data(1)[:ems_ref])
    )

    @hardware_data_12 = hardware_data(12).merge(
      :guest_os       => @persister.miq_templates.lazy_find(image_data(1)[:ems_ref], :key => :guest_os),
      :vm_or_template => @persister.vms.lazy_find(vm_data(12)[:ems_ref])
    )

    @hardware_data_2 = hardware_data(2).merge(
      :guest_os       => @persister.miq_templates.lazy_find(image_data(2)[:ems_ref], :key => :guest_os),
      :vm_or_template => @persister.vms.lazy_find(vm_data(2)[:ems_ref])
    )

    @disk_data_1 = disk_data(1).merge(
      :hardware => @persister.hardwares.lazy_find(@persister.vms.lazy_find(vm_data(1)[:ems_ref])),
    )

    @disk_data_12 = disk_data(12).merge(
      :hardware => @persister.hardwares.lazy_find(@persister.vms.lazy_find(vm_data(12)[:ems_ref])),
    )

    @disk_data_13 = disk_data(13).merge(
      :hardware => @persister.hardwares.lazy_find(@persister.vms.lazy_find(vm_data(12)[:ems_ref])),
    )

    @disk_data_2 = disk_data(2).merge(
      :hardware => @persister.hardwares.lazy_find(@persister.vms.lazy_find(vm_data(2)[:ems_ref])),
    )

    @public_network_data_1 = public_network_data(1).merge(
      :hardware => @persister.hardwares.lazy_find(@persister.vms.lazy_find(vm_data(1)[:ems_ref])),
    )

    @public_network_data_12 = public_network_data(12).merge(
      :hardware => @persister.hardwares.lazy_find(@persister.vms.lazy_find(vm_data(12)[:ems_ref])),
    )

    @public_network_data_13 = public_network_data(13).merge(
      :hardware    => @persister.hardwares.lazy_find(@persister.vms.lazy_find(vm_data(12)[:ems_ref])),
      :description => "public_2"
    )

    @public_network_data_14 = public_network_data(14).merge(
      :hardware    => @persister.hardwares.lazy_find(@persister.vms.lazy_find(vm_data(12)[:ems_ref])),
      :description => "public_2" # duplicate key, network will be ignored
    )

    @public_network_data_2 = public_network_data(2).merge(
      :hardware => @persister.hardwares.lazy_find(@persister.vms.lazy_find(vm_data(2)[:ems_ref])),
    )
  end
end
