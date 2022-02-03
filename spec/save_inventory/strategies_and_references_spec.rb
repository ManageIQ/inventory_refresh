require_relative 'spec_helper'
require_relative '../helpers/spec_parsed_data'
require_relative 'init_data_helper'

describe InventoryRefresh::SaveInventory do
  include SpecHelper
  include SpecParsedData
  include InitDataHelper

  ######################################################################################################################
  # Spec scenarios for different strategies and optimizations using references
  ######################################################################################################################

  %i(local_db_find_references local_db_cache_all).each do |db_strategy|
    context "with db strategy #{db_strategy}" do
      before do
        @ems = FactoryBot.create(:ems_cloud,
                                  :network_manager => FactoryBot.create(:ems_network))

        allow(@ems.class).to receive(:ems_type).and_return(:mock)
        @persister = persister_class.new(@ems, InventoryRefresh::TargetCollection.new(:manager => @ems))
      end

      before do
        @image1 = FactoryBot.create(:miq_template, image_data(1).merge(:ext_management_system => @ems))
        @image2 = FactoryBot.create(:miq_template, image_data(2).merge(:ext_management_system => @ems))
        @image3 = FactoryBot.create(:miq_template, image_data(3).merge(:ext_management_system => @ems))

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

        @vm1 = FactoryBot.create(
          :vm_cloud,
          vm_data(1).merge(
            :flavor    => @flavor_1,
            :location  => 'host_10_10_10_1.com',
          )
        )
        @vm12 = FactoryBot.create(
          :vm_cloud,
          vm_data(12).merge(
            :flavor    => @flavor1,
            :location  => 'host_10_10_10_12.com',
          )
        )
        @vm2 = FactoryBot.create(
          :vm_cloud,
          vm_data(2).merge(
            :flavor    => @flavor2,
            :location  => 'host_10_10_10_2.com',
          )
        )
        @vm4 = FactoryBot.create(
          :vm_cloud,
          vm_data(4).merge(
            :location              => 'default_value_unknown',
            :ext_management_system => @ems
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

      it "tests that a key pointing to a relation is filled correctly when coming from db" do
        vm_refs = %w(vm_ems_ref_3 vm_ems_ref_4)
        network_port_refs = %w(network_port_ems_ref_1)

        # Setup InventoryCollections

        network_ports_init_data(
          :parent   => @ems.network_manager,
          :arel     => @ems.network_manager.network_ports.where(:ems_ref => network_port_refs),
          :strategy => :local_db_find_missing_references
        )

        vms_init_data(
          :arel     => @ems.vms.where(:ems_ref => vm_refs),
          :strategy => :local_db_find_missing_references
        )
        hardwares_init_data(
          :arel                         => @ems.hardwares.joins(:vm_or_template).where(:vms => {:ems_ref => vm_refs}),
          :strategy                     => db_strategy,
          :parent_inventory_collections => %i(vms)
        )

        # Parse data for InventoryCollections
        @network_port_data_1 = network_port_data(1).merge(
          :device => @persister.hardwares.lazy_find(@persister.vms.lazy_find(vm_data(1)[:ems_ref]), :key => :vm_or_template)
        )

        # Fill InventoryCollections with data
        @persister.network_ports.build(@network_port_data_1)

        # Assert data before save
        @network_port1.device = nil
        @network_port1.save
        @network_port1.reload
        expect(@network_port1.device).to eq nil

        # Invoke the InventoryCollections saving
        InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

        # Assert saved data
        @network_port1.reload
        @vm1.reload
        expect(@network_port1.device).to eq @vm1
      end

      it "tests that a key pointing to a polymorphic relation is filled correctly when coming from db" do
        network_port_refs = %w(network_port_ems_ref_1)

        # Setup InventoryCollections
        network_ports_init_data(
          :association => nil,
          :parent      => @ems.network_manager,
          :arel        => @ems.network_manager.network_ports.where(:ems_ref => network_port_refs),
          :strategy    => :local_db_find_missing_references
        )
        db_network_ports_init_data(
          :parent   => @ems.network_manager,
          :strategy => db_strategy
        )

        # Parse data for InventoryCollections
        @network_port_data_1 = network_port_data(1).merge(
          :device => @persister.db_network_ports.lazy_find(network_port_data(12)[:ems_ref], :key => :device)
        )

        # Fill InventoryCollections with data
        @persister.network_ports.build(@network_port_data_1)

        # Assert data before save
        @network_port1.device = nil
        @network_port1.save
        @network_port1.reload
        expect(@network_port1.device).to eq nil

        # Invoke the InventoryCollections saving
        InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

        # Assert saved data
        @network_port1.reload
        @vm1.reload
        expect(@network_port1.device).to eq @vm1
      end

      it "saves records correctly with complex interconnection" do
        vm_refs           = %w(vm_ems_ref_3 vm_ems_ref_4)
        network_port_refs = %w(network_port_ems_ref_1 network_port_ems_ref_12)

        # Setup InventoryCollections
        miq_templates_init_data(
          :strategy => db_strategy
        )
        db_network_ports_init_data(
          :parent   => @ems.network_manager,
          :strategy => db_strategy
        )
        db_vms_init_data(
          :strategy => db_strategy
        )
        vms_init_data(
          :arel     => @ems.vms.where(:ems_ref => vm_refs),
          :strategy => :local_db_find_missing_references,
        )
        hardwares_init_data(
          :arel                         => @ems.hardwares.joins(:vm_or_template).where(:vms => {:ems_ref => vm_refs}),
          :strategy                     => :local_db_find_missing_references,
          :parent_inventory_collections => %i(vms)
        )
        network_ports_init_data(
          :parent   => @ems.network_manager,
          :arel     => @ems.network_manager.network_ports.where(:ems_ref => network_port_refs),
          :strategy => :local_db_find_missing_references
        )

        # Parse data for InventoryCollections
        @network_port_data_1 = network_port_data(1).merge(
          :name   => @persister.vms.lazy_find(vm_data(3)[:ems_ref], :key => :name),
          :device => @persister.vms.lazy_find(vm_data(3)[:ems_ref])
        )
        @network_port_data_12 = network_port_data(12).merge(
          :name   => @persister.vms.lazy_find(vm_data(4)[:ems_ref], :key => :name, :default => "default_name"),
          :device => @persister.db_network_ports.lazy_find(network_port_data(2)[:ems_ref], :key => :device)
        )
        @network_port_data_3 = network_port_data(3).merge(
          :name   => @persister.vms.lazy_find(vm_data(1)[:ems_ref], :key => :name, :default => "default_name"),
          :device => @persister.hardwares.lazy_find(@persister.vms.lazy_find(vm_data(1)[:ems_ref]), :key => :vm_or_template)
        )
        @vm_data_3 = vm_data(3).merge(
          :ext_management_system => @ems
        )
        @vm_data_31 = vm_data(31).merge(
          :ext_management_system => @ems
        )
        @hardware_data_3 = hardware_data(3).merge(
          :guest_os       => @persister.hardwares.lazy_find(@persister.miq_templates.lazy_find(image_data(2)[:ems_ref]), :key => :guest_os),
          :vm_or_template => @persister.vms.lazy_find(vm_data(3)[:ems_ref])
        )

        # Fill InventoryCollections with data
        {
          :network_ports => [@network_port_data_1,
                             @network_port_data_12,
                             @network_port_data_3],
          :vms           => [@vm_data_3,
                             @vm_data_31],
          :hardwares     => [@hardware_data_3],
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

        expect(@vm4.ext_management_system).to eq @ems

        # Invoke the InventoryCollections saving
        InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

        #### Assert saved data ####
        @vm3           = Vm.find_by(:ems_ref => vm_data(3)[:ems_ref])
        @vm31          = Vm.find_by(:ems_ref => vm_data(31)[:ems_ref])
        @vm4           = Vm.find_by(:ems_ref => vm_data(4)[:ems_ref])
        @network_port3 = NetworkPort.find_by(:ems_ref => network_port_data(3)[:ems_ref])
        @network_port1.reload
        @network_port12.reload
        @vm4.reload
        # @image2.reload will not refresh STI class, we should probably extend the factory with the right class
        @image2 = MiqTemplate.find(@image2.id)

        expect(@network_port1.device).to eq @vm3
        expect(@network_port1.name).to eq "vm_name_3"
        expect(@network_port12.device).to eq @vm2
        # Vm4 name was not found, because @vm4 got disconnected and no longer can be found in ems.vms
        expect(@network_port12.name).to eq "default_name"
        expect(@network_port3.device).to eq @vm1
        expect(@network_port3.name).to eq "vm_name_1"
        expect(@vm3.hardware.guest_os).to eq "linux_generic_2"
        # We don't support :key pointing to a has_many, so it default to []
        expect(@vm31.hardware).to be_nil
        # Check Vm4 was disconnected
        expect(@vm4.archived_at).not_to be_nil
      end
    end
  end
end
