require_relative 'spec_helper'
require_relative '../helpers/spec_parsed_data'
require_relative 'init_data_helper'

describe InventoryRefresh::SaveInventory do
  include SpecHelper
  include SpecParsedData
  include InitDataHelper

  ######################################################################################################################
  # Spec scenarios for saver strategies
  ######################################################################################################################

  [
    {:saver_strategy => :default},
    {:saver_strategy => :batch, :use_ar_object => true},
    {:saver_strategy => :batch, :use_ar_object => false},
  ].each do |options|
    context "with options #{options}" do
      before do
        @ems = FactoryBot.create(:ems_cloud,
                                  :network_manager => FactoryBot.create(:ems_network))

        allow(@ems.class).to receive(:ems_type).and_return(:mock)
        @persister = persister_class.new(@ems, InventoryRefresh::TargetCollection.new(:manager => @ems))
      end

      before do
        @image1 = FactoryBot.create(:miq_template, image_data(1))
        @image2 = FactoryBot.create(:miq_template, image_data(2))
        @image3 = FactoryBot.create(:miq_template, image_data(3))

        @image_hardware1 = FactoryBot.create(
          :hardware,
          image_hardware_data(1).merge(
            :guest_os       => "linux_generic_1",
            :vm_or_template => @image1
          )
        )
        @image_hardware2 = FactoryBot.create(
          :hardware,
          image_hardware_data(2).merge(
            :guest_os       => "linux_generic_2",
            :vm_or_template => @image2
          )
        )
        @image_hardware3 = FactoryBot.create(
          :hardware,
          image_hardware_data(3).merge(
            :guest_os       => "linux_generic_3",
            :vm_or_template => @image3
          )
        )

        @key_pair1  = FactoryBot.create(:auth_key_pair_cloud, key_pair_data(1))
        @key_pair12 = FactoryBot.create(:auth_key_pair_cloud, key_pair_data(12))
        @key_pair2  = FactoryBot.create(:auth_key_pair_cloud, key_pair_data(2))
        @key_pair3  = FactoryBot.create(:auth_key_pair_cloud, key_pair_data(3))

        @vm1 = FactoryBot.create(
          :vm_cloud,
          vm_data(1).merge(
            :flavor    => @flavor_1,
            :key_pairs => [@key_pair1],
            :location  => 'host_10_10_10_1.com',
          )
        )
        @vm12 = FactoryBot.create(
          :vm_cloud,
          vm_data(12).merge(
            :flavor    => @flavor1,
            :key_pairs => [@key_pair1, @key_pair12],
            :location  => 'host_10_10_10_12.com',
          )
        )
        @vm2 = FactoryBot.create(
          :vm_cloud,
          vm_data(2).merge(
            :flavor    => @flavor2,
            :key_pairs => [@key_pair2],
            :location  => 'host_10_10_10_2.com',
          )
        )
        @vm4 = FactoryBot.create(
          :vm_cloud,
          vm_data(4).merge(
            :location => 'default_value_unknown',
          )
        )

        @hardware1 = FactoryBot.create(
          :hardware,
          hardware_data(1).merge(
            :guest_os       => @image1.hardware.guest_os,
            :vm_or_template => @vm1
          )
        )
        @hardware12 = FactoryBot.create(
          :hardware,
          hardware_data(12).merge(
            :guest_os       => @image1.hardware.guest_os,
            :vm_or_template => @vm12
          )
        )
        @hardware2 = FactoryBot.create(
          :hardware,
          hardware_data(2).merge(
            :guest_os       => @image2.hardware.guest_os,
            :vm_or_template => @vm2
          )
        )

        @network_port1 = FactoryBot.create(
          :network_port,
          network_port_data(1).merge(
            :device => @vm1
          )
        )

        @network_port12 = FactoryBot.create(
          :network_port,
          network_port_data(12).merge(
            :device => @vm1
          )
        )

        @network_port2 = FactoryBot.create(
          :network_port,
          network_port_data(2).merge(
            :device => @vm2
          )
        )

        @network_port4 = FactoryBot.create(
          :network_port,
          network_port_data(4).merge(
            :device => @vm4
          )
        )
      end

      it "saves records correctly with complex interconnection" do
        # Setup InventoryCollections
        miq_templates_init_data(inventory_collection_options(options))

        key_pairs_init_data(inventory_collection_options(options))

        vms_init_data(inventory_collection_options(options))

        hardwares_init_data(inventory_collection_options(options))

        network_ports_init_data(
          inventory_collection_options(
            options.merge(
              :parent => @ems.network_manager
            )
          )
        )

        # Parse data for InventoryCollections
        @network_port_data_1 = network_port_data(1).merge(
          :name   => @persister.vms.lazy_find(vm_data(1)[:ems_ref], :key => :name, :default => "default_name"),
          :device => @persister.vms.lazy_find(vm_data(1)[:ems_ref])
        )
        @network_port_data_12 = network_port_data(12).merge(
          :name   => @persister.vms.lazy_find(vm_data(31)[:ems_ref], :key => :name, :default => "default_name"),
          :device => @persister.vms.lazy_find(vm_data(31)[:ems_ref])
        )
        @network_port_data_3 = network_port_data(3).merge(
          :name   => @persister.vms.lazy_find(vm_data(3)[:ems_ref], :key => :name, :default => "default_name"),
          :device => @persister.vms.lazy_find(vm_data(3)[:ems_ref])
        )
        @vm_data_1 = vm_data(1)
        @vm_data_2 = vm_data(2).merge(
          :name => "vm_2_changed_name",
        )
        @vm_data_3 = vm_data(3).merge(
          :name => "vm_3_changed_name",
        )
        @vm_data_31 = vm_data(31).merge(
          :name => "vm_31_changed_name",
        )
        @hardware_data_2 = hardware_data(2).merge(
          :guest_os       => @persister.hardwares.lazy_find(@persister.miq_templates.lazy_find(image_data(1)[:ems_ref]), :key => :guest_os), # changed
          :vm_or_template => @persister.vms.lazy_find(vm_data(2)[:ems_ref])
        )
        @hardware_data_3 = hardware_data(3).merge(
          :guest_os       => @persister.hardwares.lazy_find(@persister.miq_templates.lazy_find(image_data(2)[:ems_ref]), :key => :guest_os),
          :vm_or_template => @persister.vms.lazy_find(vm_data(3)[:ems_ref])
        )
        @hardware_data_31 = hardware_data(31).merge(
          :guest_os       => @persister.hardwares.lazy_find(@persister.miq_templates.lazy_find(image_data(2)[:ems_ref]), :key => :guest_os),
          :vm_or_template => @persister.vms.lazy_find(vm_data(31)[:ems_ref])
        )

        @image_data_2 = image_data(2).merge(:name => "image_changed_name_2")
        @image_data_3 = image_data(3).merge(:name => "image_changed_name_3")

        # Fill InventoryCollections with data
        {
          :network_ports => [@network_port_data_1,
                             @network_port_data_12,
                             @network_port_data_3],
          :vms           => [@vm_data_2,
                             @vm_data_3,
                             @vm_data_31],
          :miq_templates => [@image_data_2,
                             @image_data_3],
          :hardwares     => [@hardware_data_2,
                             @hardware_data_3,
                             @hardware_data_31],
        }.each_pair do |inventory_collection_name, data_arr|
          data_arr.each do |data|
            @persister.send(inventory_collection_name).build(data)
          end
        end

        # Assert data before save
        expect(@network_port1.device).to eq @vm1
        expect(@network_port1.name).to eq "network_port_name_1"

        expect(@network_port12.device).to eq @vm1
        expect(@network_port12.name).to eq "network_port_name_12"

        sleep(1)
        time_before_refresh = Time.now.utc
        sleep(1)
        # Invoke the InventoryCollections saving
        InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

        #### Assert saved data ####
        @vm1           = Vm.find_by(:ems_ref => vm_data(1)[:ems_ref])
        @vm12          = Vm.find_by(:ems_ref => vm_data(12)[:ems_ref])
        @vm2           = Vm.find_by(:ems_ref => vm_data(2)[:ems_ref])
        @vm3           = Vm.find_by(:ems_ref => vm_data(3)[:ems_ref])
        @vm31          = Vm.find_by(:ems_ref => vm_data(31)[:ems_ref])
        @vm4           = Vm.find_by(:ems_ref => vm_data(4)[:ems_ref])
        @network_port3 = NetworkPort.find_by(:ems_ref => network_port_data(3)[:ems_ref])
        @network_port1.reload
        @network_port12.reload

        @image2 = MiqTemplate.find(@image2.id)

        # Check ICs stats
        expect(@persister.vms.created_records).to match_array(record_stats([@vm3, @vm31]))
        expect(@persister.vms.deleted_records).to match_array(record_stats([@vm1, @vm12, @vm4]))
        expect(@persister.vms.updated_records).to match_array(record_stats([@vm2]))

        expect(@persister.network_ports.created_records).to match_array(record_stats([@network_port3]))
        expect(@persister.network_ports.deleted_records).to match_array(record_stats([@network_port2, @network_port4]))
        expect(@persister.network_ports.updated_records).to match_array(record_stats([@network_port1, @network_port12]))

        expect(@persister.hardwares.created_records).to match_array(record_stats([@vm3.hardware, @vm31.hardware]))
        # We don't see hardwares that were disconnected as a part of Vm or Template
        expect(@persister.hardwares.deleted_records).to match_array(record_stats([@image_hardware2, @image_hardware3]))
        expect(@persister.hardwares.updated_records).to match_array(record_stats([@hardware2]))

        expect(@persister.miq_templates.created_records).to match_array(record_stats([]))
        expect(@persister.miq_templates.deleted_records).to match_array(record_stats([@image1]))
        expect(@persister.miq_templates.updated_records).to match_array(record_stats([@image2, @image3]))

        expect(@persister.key_pairs.created_records).to match_array(record_stats([]))
        expect(@persister.key_pairs.deleted_records).to match_array(record_stats([@key_pair1, @key_pair12, @key_pair2, @key_pair3]))
        expect(@persister.key_pairs.updated_records).to match_array(record_stats([]))

        # Check the changed timestamps
        expect(@vm3.created_on).to be > time_before_refresh
        expect(@vm3.updated_on).to be > time_before_refresh
        expect(@vm31.created_on).to be > time_before_refresh
        expect(@vm31.updated_on).to be > time_before_refresh

        expect(@vm2.created_on).to be < time_before_refresh
        expect(@vm2.updated_on).to be > time_before_refresh

        # Check DB data
        expect(@network_port1.device).to eq nil
        expect(@network_port12.device).to eq @vm31
        expect(@vm31.hardware).not_to be_nil
        expect(@network_port3.device).to eq @vm3

        assert_all_records_match_hashes(
          [::ManageIQ::Providers::CloudManager::Vm.all],
          {
            :id       => @vm1.id,
            :ems_ref  => "vm_ems_ref_1",
            :ems_id   => nil,
            :name     => "vm_name_1",
            :location => "host_10_10_10_1.com"
          }, {
            :id       => @vm12.id,
            :ems_ref  => "vm_ems_ref_12",
            :ems_id   => nil,
            :name     => "vm_name_12",
            :location => "host_10_10_10_12.com"
          }, {
            :id       => @vm2.id,
            :ems_ref  => "vm_ems_ref_2",
            :ems_id   => @ems.id,
            :name     => "vm_2_changed_name",
            :location => "vm_location_2"
          }, {
            :id       => @vm4.id,
            :ems_ref  => "vm_ems_ref_4",
            :ems_id   => nil,
            :name     => "vm_name_4",
            :location => "default_value_unknown"
          }, {
            :id       => @vm3.id,
            :ems_ref  => "vm_ems_ref_3",
            :ems_id   => @ems.id,
            :name     => "vm_3_changed_name",
            :location => "vm_location_3"
          }, {
            :id       => @vm31.id,
            :ems_ref  => "vm_ems_ref_31",
            :ems_id   => @ems.id,
            :name     => "vm_31_changed_name",
            :location => "vm_location_31"
          }
        )

        assert_all_records_match_hashes(
          [Hardware.all],
          {:vm_or_template_id => @image1.id, :guest_os => "linux_generic_1"},
          {:vm_or_template_id => @vm1.id, :guest_os => "linux_generic_1"},
          {:vm_or_template_id => @vm2.id, :guest_os => nil},
          {:vm_or_template_id => @vm12.id, :guest_os => "linux_generic_1"},
          {:vm_or_template_id => @vm3.id, :guest_os => "linux_generic_2"},
          {:vm_or_template_id => @vm31.id, :guest_os => "linux_generic_2"}
        )

        assert_all_records_match_hashes(
          [NetworkPort.all],
          {
            :id          => @network_port1.id,
            :ems_id      => @ems.network_manager.id,
            :name        => "default_name",
            :mac_address => "network_port_mac_1",
            :device_id   => nil,
            :device_type => nil
          }, {
            :id          => @network_port12.id,
            :ems_id      => @ems.network_manager.id,
            :name        => "vm_31_changed_name",
            :mac_address => "network_port_mac_12",
            :device_id   => @vm31.id,
            :device_type => "VmOrTemplate"
          }, {
            :id          => @network_port3.id,
            :ems_id      => @ems.network_manager.id,
            :name        => "vm_3_changed_name",
            :mac_address => "network_port_mac_3",
            :device_id   => @vm3.id,
            :device_type => "VmOrTemplate"
          }
        )

        assert_all_records_match_hashes(
          [ManageIQ::Providers::CloudManager::Template.all],
          {
            :id       => @image1.id,
            :ems_ref  => "image_ems_ref_1",
            :ems_id   => nil,
            :name     => "image_name_1",
            :location => "image_location_1"
          }, {
            :id       => @image2.id,
            :ems_ref  => "image_ems_ref_2",
            :ems_id   => @ems.id,
            :name     => "image_changed_name_2",
            :location => "image_location_2"
          }, {
            :id       => @image3.id,
            :ems_ref  => "image_ems_ref_3",
            :ems_id   => @ems.id,
            :name     => "image_changed_name_3",
            :location => "image_location_3"
          }
        )

        expect(::ManageIQ::Providers::CloudManager::AuthKeyPair.all).to eq([])
      end
    end
  end

  def inventory_collection_options(extra_options)
    {
      :strategy => :local_db_find_missing_references
    }.merge(extra_options)
  end

  def record_stats(records)
    records.map do |x|
      {:id => x.id}
    end
  end
end
