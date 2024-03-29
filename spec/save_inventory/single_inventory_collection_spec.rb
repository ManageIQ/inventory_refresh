require_relative 'spec_helper'
require_relative '../helpers/spec_parsed_data'
require_relative '../helpers/test_persister'

describe InventoryRefresh::SaveInventory do
  include SpecHelper
  include SpecParsedData

  ######################################################################################################################
  #
  # Testing SaveInventory for one InventoryCollection with Vm data and various InventoryCollection constructor
  # attributes, to verify that saving of one isolated InventoryCollection works correctly for Full refresh, Targeted
  # refresh, Skeletal refresh or any other variations of refreshes that needs to save partial or complete collection
  # with partial or complete data.
  #
  ######################################################################################################################

  let(:persister_class) { ::TestPersister }

  before do
    @ems = FactoryBot.create(:ems_cloud)

    allow(@ems.class).to receive(:ems_type).and_return(:mock)
    @persister = persister_class.new(@ems, InventoryRefresh::TargetCollection.new(:manager => @ems))
  end

  context 'with no Vms in the DB' do
    it 'creates VMs' do
      # Initialize the InventoryCollections
      @persister.add_collection(:vms) do |builder|
        builder.add_properties(
          :model_class => ManageIQ::Providers::CloudManager::Vm
        )
      end
      (1..2).each { |i| @persister.vms.build(vm_data(i)) }

      # Invoke the InventoryCollections saving
      InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

      # Assert saved data
      assert_all_records_match_hashes(
        [Vm.all, @ems.vms],
        {:ems_ref => "vm_ems_ref_1", :name => "vm_name_1", :location => "vm_location_1"},
        {:ems_ref => "vm_ems_ref_2", :name => "vm_name_2", :location => "vm_location_2"}
      )
    end

    it 'creates and updates VMs' do
      # Initialize the InventoryCollections
      @persister.add_collection(:vms) do |builder|
        builder.add_properties(
          :model_class => ManageIQ::Providers::CloudManager::Vm
        )
      end

      (1..2).each { |i| @persister.vms.build(vm_data(i)) }

      # Invoke the InventoryCollections saving
      InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

      # Assert that saved data have the updated values, checking id to make sure the original records are updated
      assert_all_records_match_hashes(
        [Vm.all, @ems.vms],
        {:ems_ref => "vm_ems_ref_1", :name => "vm_name_1", :location => "vm_location_1"},
        {:ems_ref => "vm_ems_ref_2", :name => "vm_name_2", :location => "vm_location_2"}
      )

      # Fetch the created Vms from the DB
      vm1 = Vm.find_by(:ems_ref => "vm_ems_ref_1")
      vm2 = Vm.find_by(:ems_ref => "vm_ems_ref_2")

      # Second saving with the updated data
      # Initialize the InventoryCollections
      data = {}
      data[:vms] = ::InventoryRefresh::InventoryCollection.new(
        :model_class => ManageIQ::Providers::CloudManager::Vm, :parent => @ems, :association => :vms
      )
      @persister.add_collection(:vms) do |builder|
        builder.add_properties(
          :model_class => ManageIQ::Providers::CloudManager::Vm
        )
      end
      (1..2).each { |i| @persister.vms.build(vm_data(i).merge(:name => "vm_changed_name_#{i}")) }

      # Invoke the InventoryCollections saving
      InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

      # Assert that saved data have the updated values, checking id to make sure the original records are updated
      assert_all_records_match_hashes(
        [Vm.all, @ems.vms],
        {:id => vm1.id, :ems_ref => "vm_ems_ref_1", :name => "vm_changed_name_1", :location => "vm_location_1"},
        {:id => vm2.id, :ems_ref => "vm_ems_ref_2", :name => "vm_changed_name_2", :location => "vm_location_2"}
      )
    end
  end

  context 'with existing Vms in the DB' do
    before do
      # Fill DB with test Vms
      @vm1 = FactoryBot.create(:vm_cloud, vm_data(1).merge(:ext_management_system => @ems))
      @vm2 = FactoryBot.create(:vm_cloud, vm_data(2).merge(:ext_management_system => @ems))
    end

    context 'with VM InventoryCollection with default settings' do
      before do
        @persister.add_collection(:vms) do |builder|
          builder.add_properties(
            :model_class => ManageIQ::Providers::CloudManager::Vm
          )
        end
      end

      it 'has correct records in the DB' do
        # Check we really have the expected Vms in the DB
        assert_all_records_match_hashes(
          [Vm.all, @ems.vms],
          {:ems_ref => "vm_ems_ref_1", :name => "vm_name_1", :location => "vm_location_1"},
          {:ems_ref => "vm_ems_ref_2", :name => "vm_name_2", :location => "vm_location_2"}
        )
      end

      it 'updates existing VMs' do
        # Fill the InventoryCollections with data, that have a modified name
        (1..2).each { |i| @persister.vms.build(vm_data(i).merge(:name => "vm_changed_name_#{i}")) }

        # Invoke the InventoryCollections saving
        InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

        # Check the InventoryCollection result matches what was created/deleted/updated
        expect(@persister.vms.created_records).to match_array([])
        expect(@persister.vms.updated_records).to match_array([{:id => @vm1.id}, {:id => @vm2.id}])
        expect(@persister.vms.deleted_records).to match_array([])

        # Assert that saved data have the updated values, checking id to make sure the original records are updated
        assert_all_records_match_hashes(
          [Vm.all, @ems.vms],
          {:id => @vm1.id, :ems_ref => "vm_ems_ref_1", :name => "vm_changed_name_1", :location => "vm_location_1"},
          {:id => @vm2.id, :ems_ref => "vm_ems_ref_2", :name => "vm_changed_name_2", :location => "vm_location_2"}
        )
      end

      it 'updates 1 existing VM' do
        # Fill the InventoryCollections with data, that have a modified name
        @persister.vms.build(vm_data(1))
        @persister.vms.build(vm_data(2).merge(:name => "vm_changed_name_2"))

        # Invoke the InventoryCollections saving
        InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

        # Check the InventoryCollection result matches what was created/deleted/updated
        expect(@persister.vms.created_records).to match_array([])
        expect(@persister.vms.updated_records).to match_array([{:id => @vm2.id}])
        expect(@persister.vms.deleted_records).to match_array([])

        # Assert that saved data have the updated values, checking id to make sure the original records are updated
        assert_all_records_match_hashes(
          [Vm.all, @ems.vms],
          {:id => @vm1.id, :ems_ref => "vm_ems_ref_1", :name => "vm_name_1", :location => "vm_location_1"},
          {:id => @vm2.id, :ems_ref => "vm_ems_ref_2", :name => "vm_changed_name_2", :location => "vm_location_2"}
        )
      end

      it 'creates new VMs' do
        # Fill the InventoryCollections with data, that have a new VM
        (1..3).each { |i| @persister.vms.build(vm_data(i).merge(:name => "vm_changed_name_#{i}")) }

        # Invoke the InventoryCollections saving
        InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

        # Check the InventoryCollection result matches what was created/deleted/updated
        @vm3 = Vm.find_by(:ems_ref => "vm_ems_ref_3")
        expect(@persister.vms.created_records).to match_array([{:id => @vm3.id}])
        expect(@persister.vms.updated_records).to match_array([{:id => @vm1.id}, {:id => @vm2.id}])
        expect(@persister.vms.deleted_records).to match_array([])

        # Assert that saved data contain the new VM
        assert_all_records_match_hashes(
          [Vm.all, @ems.vms],
          {:id => @vm1.id, :ems_ref => "vm_ems_ref_1", :name => "vm_changed_name_1", :location => "vm_location_1"},
          {:id => @vm2.id, :ems_ref => "vm_ems_ref_2", :name => "vm_changed_name_2", :location => "vm_location_2"},
          {:id => anything, :ems_ref => "vm_ems_ref_3", :name => "vm_changed_name_3", :location => "vm_location_3"}
        )
      end

      it 'deletes missing VMs' do
        # Fill the InventoryCollections with data, that are missing one VM
        @persister.vms.build(vm_data(1).merge(:name => "vm_changed_name_1"))

        # Invoke the InventoryCollections saving
        InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

        # Check the InventoryCollection result matches what was created/deleted/updated
        expect(@persister.vms.created_records).to match_array([])
        expect(@persister.vms.updated_records).to match_array([{:id => @vm1.id}])
        expect(@persister.vms.deleted_records).to match_array([{:id => @vm2.id}])

        # Assert that saved data do miss the deleted VM
        assert_all_records_match_hashes(
          [Vm.all, @ems.vms],
          :id => @vm1.id, :ems_ref => "vm_ems_ref_1", :name => "vm_changed_name_1", :location => "vm_location_1"
        )
      end

      it 'deletes missing and creates new VMs' do
        # Fill the InventoryCollections with data, that have one new VM and are missing one VM
        %w[1 3].each { |i| @persister.vms.build(vm_data(i).merge(:name => "vm_changed_name_#{i}")) }

        # Invoke the InventoryCollections saving
        InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

        # Check the InventoryCollection result matches what was created/deleted/updated
        @vm3 = Vm.find_by(:ems_ref => "vm_ems_ref_3")
        expect(@persister.vms.created_records).to match_array([{:id => @vm3.id}])
        expect(@persister.vms.updated_records).to match_array([{:id => @vm1.id}])
        expect(@persister.vms.deleted_records).to match_array([{:id => @vm2.id}])

        # Assert that saved data have the new VM and miss the deleted VM
        assert_all_records_match_hashes(
          [Vm.all, @ems.vms],
          {:id => @vm1.id, :ems_ref => "vm_ems_ref_1", :name => "vm_changed_name_1", :location => "vm_location_1"},
          {:id => anything, :ems_ref => "vm_ems_ref_3", :name => "vm_changed_name_3", :location => "vm_location_3"}
        )
      end
    end

    context 'with VM InventoryCollection with :delete_method => :disconnect_inv' do
      before do
        # Initialize the InventoryCollections
        @persister.add_collection(:vms) do |builder|
          builder.add_properties(
            :model_class   => ManageIQ::Providers::CloudManager::Vm,
            :delete_method => :disconnect_inv
          )
        end
      end

      it 'disconnects a missing VM instead of deleting it' do
        # Fill the InventoryCollections with data, that have a modified name, new VM and a missing VM
        %w[1 3].each { |i| @persister.vms.build(vm_data(i).merge(:name => "vm_changed_name_#{i}")) }

        # Invoke the InventoryCollections saving
        InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

        # Assert that DB still contains the disconnected VMs
        assert_all_records_match_hashes(
          Vm.all,
          {:id => @vm1.id, :ems_ref => "vm_ems_ref_1", :name => "vm_changed_name_1", :location => "vm_location_1"},
          {:id => @vm2.id, :ems_ref => "vm_ems_ref_2", :name => "vm_name_2", :location => "vm_location_2"},
          {:id => anything, :ems_ref => "vm_ems_ref_3", :name => "vm_changed_name_3", :location => "vm_location_3"}
        )

        # Assert that ems do not have the disconnected VMs associated
        assert_all_records_match_hashes(
          @ems.vms,
          {:id => @vm1.id, :ems_ref => "vm_ems_ref_1", :name => "vm_changed_name_1", :location => "vm_location_1"},
          {:id => anything, :ems_ref => "vm_ems_ref_3", :name => "vm_changed_name_3", :location => "vm_location_3"}
        )
      end
    end

    context 'with VM InventoryCollection blacklist or whitelist used' do
      let :changed_data do
        [
          vm_data(1).merge(:name            => "vm_changed_name_1",
                           :location        => "vm_changed_location_1",
                           :uid_ems         => "uid_ems_changed_1",
                           :raw_power_state => "raw_power_state_changed_1"),
          vm_data(2).merge(:name            => "vm_changed_name_2",
                           :location        => "vm_changed_location_2",
                           :uid_ems         => "uid_ems_changed_2",
                           :raw_power_state => "raw_power_state_changed_2"),
          vm_data(3).merge(:name            => "vm_changed_name_3",
                           :location        => "vm_changed_location_3",
                           :uid_ems         => "uid_ems_changed_3",
                           :raw_power_state => "raw_power_state_changed_3")
        ]
      end

      # TODO(lsmola) fixed attributes should contain also other attributes, like inclusion validation of :vendor
      # column
      it 'recognizes correct presence validators' do
        @persister.add_collection(:vms) do |builder|
          builder.add_properties(
            :model_class          => ManageIQ::Providers::CloudManager::Vm,
            :attributes_blacklist => %i[ems_ref uid_ems name location]
          )
        end
        # Check that :name and :location do have validate presence, those attributes will not be blacklisted
        presence_validators = @persister.vms.model_class.validators
                                        .detect { |x| x.kind_of? ActiveRecord::Validations::PresenceValidator }.attributes

        expect(presence_validators).to include(:name)
        expect(presence_validators).to include(:location)
      end

      it 'does not blacklist fixed attributes with default manager_ref' do
        # Fixed attributes are attributes used for unique ID of the DTO or attributes with presence validation
        @persister.add_collection(:vms) do |builder|
          builder.add_properties(
            :model_class          => ManageIQ::Providers::CloudManager::Vm,
            :attributes_blacklist => %i[ems_ref uid_ems name location vendor raw_power_state]
          )
        end
        expect(@persister.vms.attributes_blacklist).to match_array(%i[vendor uid_ems raw_power_state])
      end

      it 'has fixed and internal attributes amongst whitelisted_attributes with default manager_ref' do
        # Fixed attributes are attributes used for unique ID of the DTO or attributes with presence validation
        @persister.add_collection(:vms) do |builder|
          builder.add_properties(
            :model_class          => ManageIQ::Providers::CloudManager::Vm,
            :attributes_whitelist => %i[raw_power_state ext_management_system]
          )
        end

        expect(@persister.vms.attributes_whitelist).to match_array(%i[__feedback_edge_set_parent
                                                                      __parent_inventory_collections
                                                                      __all_manager_uuids_scope
                                                                      ems_ref
                                                                      name
                                                                      location
                                                                      raw_power_state
                                                                      ext_management_system])
      end

      it 'does not blacklist fixed attributes when changing manager_ref' do
        @persister.add_collection(:vms) do |builder|
          builder.add_properties(
            :model_class          => ManageIQ::Providers::CloudManager::Vm,
            :manager_ref          => %i[uid_ems],
            :attributes_blacklist => %i[ems_ref uid_ems name location vendor raw_power_state]
          )
        end
        expect(@persister.vms.attributes_blacklist).to match_array(%i[vendor ems_ref raw_power_state])
      end

      it 'has fixed and internal attributes amongst whitelisted_attributes when changing manager_ref' do
        # Fixed attributes are attributes used for unique ID of the DTO or attributes with presence validation
        @persister.add_collection(:vms) do |builder|
          builder.add_properties(
            :model_class          => ManageIQ::Providers::CloudManager::Vm,
            :manager_ref          => %i[uid_ems],
            :attributes_whitelist => %i[raw_power_state ext_management_system]
          )
        end
        expect(@persister.vms.attributes_whitelist).to match_array(%i[__feedback_edge_set_parent
                                                                      __parent_inventory_collections
                                                                      __all_manager_uuids_scope
                                                                      uid_ems
                                                                      name
                                                                      location
                                                                      raw_power_state
                                                                      ext_management_system])
      end

      it 'saves all attributes with blacklist and whitelist disabled' do
        # Initialize the InventoryCollections
        @persister.add_collection(:vms) do |builder|
          builder.add_properties(
            :model_class => ManageIQ::Providers::CloudManager::Vm
          )
        end

        # Fill the InventoryCollections with data, that have a modified name, new VM and a missing VM
        changed_data.each { |vm_data| @persister.vms.build(vm_data) }

        # Invoke the InventoryCollections saving
        InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

        # Assert that saved data don;t have the blacklisted attributes updated nor filled
        assert_all_records_match_hashes(
          [Vm.all, @ems.vms],
          {:id              => @vm1.id,
           :ems_ref         => "vm_ems_ref_1",
           :name            => "vm_changed_name_1",
           :raw_power_state => "raw_power_state_changed_1",
           :uid_ems         => "uid_ems_changed_1",
           :location        => "vm_changed_location_1"},
          {:id              => @vm2.id,
           :ems_ref         => "vm_ems_ref_2",
           :name            => "vm_changed_name_2",
           :raw_power_state => "raw_power_state_changed_2",
           :uid_ems         => "uid_ems_changed_2",
           :location        => "vm_changed_location_2"},
          {:id              => anything,
           :ems_ref         => "vm_ems_ref_3",
           :name            => "vm_changed_name_3",
           :raw_power_state => "raw_power_state_changed_3",
           :uid_ems         => "uid_ems_changed_3",
           :location        => "vm_changed_location_3"}
        )
      end

      it 'does not save blacklisted attributes (excluding fixed attributes)' do
        # Initialize the InventoryCollections
        @persister.add_collection(:vms) do |builder|
          builder.add_properties(
            :model_class          => ManageIQ::Providers::CloudManager::Vm,
            :attributes_blacklist => %i[name location raw_power_state]
          )
        end
        # Fill the InventoryCollections with data, that have a modified name, new VM and a missing VM
        changed_data.each { |vm_data| @persister.vms.build(vm_data) }

        # Invoke the InventoryCollections saving
        InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

        # Assert that saved data don;t have the blacklisted attributes updated nor filled
        assert_all_records_match_hashes(
          [Vm.all, @ems.vms],
          {:id              => @vm1.id,
           :ems_ref         => "vm_ems_ref_1",
           :name            => "vm_changed_name_1",
           :raw_power_state => "unknown",
           :uid_ems         => "uid_ems_changed_1",
           :location        => "vm_changed_location_1"},
          {:id              => @vm2.id,
           :ems_ref         => "vm_ems_ref_2",
           :name            => "vm_changed_name_2",
           :raw_power_state => "unknown",
           :uid_ems         => "uid_ems_changed_2",
           :location        => "vm_changed_location_2"},
          {:id              => anything,
           :ems_ref         => "vm_ems_ref_3",
           :name            => "vm_changed_name_3",
           :raw_power_state => nil,
           :uid_ems         => "uid_ems_changed_3",
           :location        => "vm_changed_location_3"}
        )
      end

      it 'saves only whitelisted attributes (including fixed attributes)' do
        # Initialize the InventoryCollections
        @persister.add_collection(:vms) do |builder|
          builder.add_properties(
            :model_class          => ManageIQ::Providers::CloudManager::Vm,
            # TODO(lsmola) vendor is not getting caught by fixed attributes
            :attributes_whitelist => %i[uid_ems vendor ext_management_system ems_id]
          )
        end

        # Fill the InventoryCollections with data, that have a modified name, new VM and a missing VM
        changed_data.each { |vm_data| @persister.vms.build(vm_data) }

        # Invoke the InventoryCollections saving
        InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

        # Assert that saved data don;t have the blacklisted attributes updated nor filled
        assert_all_records_match_hashes(
          [Vm.all, @ems.vms],
          {:id              => @vm1.id,
           :ems_ref         => "vm_ems_ref_1",
           :name            => "vm_changed_name_1",
           :raw_power_state => "unknown",
           :uid_ems         => "uid_ems_changed_1",
           :location        => "vm_changed_location_1"},
          {:id              => @vm2.id,
           :ems_ref         => "vm_ems_ref_2",
           :name            => "vm_changed_name_2",
           :raw_power_state => "unknown",
           :uid_ems         => "uid_ems_changed_2",
           :location        => "vm_changed_location_2"},
          {:id              => anything,
           :ems_ref         => "vm_ems_ref_3",
           :name            => "vm_changed_name_3",
           :raw_power_state => nil,
           :uid_ems         => "uid_ems_changed_3",
           :location        => "vm_changed_location_3"}
        )
      end

      it 'saves correct set of attributes when both whilelist and blacklist are used' do
        # Initialize the InventoryCollections
        @persister.add_collection(:vms) do |builder|
          builder.add_properties(
            :model_class          => ManageIQ::Providers::CloudManager::Vm,
            # TODO(lsmola) vendor is not getting caught by fixed attributes
            :attributes_whitelist => %i[uid_ems raw_power_state vendor ems_id ext_management_system],
            :attributes_blacklist => %i[name ems_ref raw_power_state]
          )
        end
        # Fill the InventoryCollections with data, that have a modified name, new VM and a missing VM
        changed_data.each { |vm_data| @persister.vms.build(vm_data) }

        # Invoke the InventoryCollections saving
        InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

        # Assert that saved data don;t have the blacklisted attributes updated nor filled
        assert_all_records_match_hashes(
          [Vm.all, @ems.vms],
          {:id              => @vm1.id,
           :ems_ref         => "vm_ems_ref_1",
           :name            => "vm_changed_name_1",
           :raw_power_state => "unknown",
           :uid_ems         => "uid_ems_changed_1",
           :location        => "vm_changed_location_1"},
          {:id              => @vm2.id,
           :ems_ref         => "vm_ems_ref_2",
           :name            => "vm_changed_name_2",
           :raw_power_state => "unknown",
           :uid_ems         => "uid_ems_changed_2",
           :location        => "vm_changed_location_2"},
          {:id              => anything,
           :ems_ref         => "vm_ems_ref_3",
           :name            => "vm_changed_name_3",
           :raw_power_state => nil,
           :uid_ems         => "uid_ems_changed_3",
           :location        => "vm_changed_location_3"}
        )
      end
    end

    context 'with VM InventoryCollection with :complete => false' do
      before do
        # Initialize the InventoryCollections
        @persister.add_collection(:vms) do |builder|
          builder.add_properties(
            :model_class => ManageIQ::Providers::CloudManager::Vm,
            :complete    => false
          )
        end
      end

      it 'updates only existing VMs and creates new VMs, does not delete or update missing VMs' do
        # Fill the InventoryCollections with data, that have a new VM
        %w[1 3].each { |i| @persister.vms.build(vm_data(i).merge(:name => "vm_changed_name_#{i}")) }

        # Invoke the InventoryCollections saving
        InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

        # Assert that saved data contain the new VM, but no VM was deleted
        assert_all_records_match_hashes(
          [Vm.all, @ems.vms],
          {:id => @vm1.id, :ems_ref => "vm_ems_ref_1", :name => "vm_changed_name_1", :location => "vm_location_1"},
          {:id => @vm2.id, :ems_ref => "vm_ems_ref_2", :name => "vm_name_2", :location => "vm_location_2"},
          {:id => anything, :ems_ref => "vm_ems_ref_3", :name => "vm_changed_name_3", :location => "vm_location_3"}
        )
      end
    end

    context 'with VM InventoryCollection with changed parent and association' do
      it 'deletes missing and creates new VMs with AvailabilityZone parent, ' do
        availability_zone = FactoryBot.create(:availability_zone, :ext_management_system => @ems)
        @vm1.update(:availability_zone => availability_zone)
        @vm2.update(:availability_zone => availability_zone)

        # Initialize the InventoryCollections
        @persister.add_collection(:vms) do |builder|
          builder.add_properties(
            :model_class => ManageIQ::Providers::CloudManager::Vm,
            :parent      => availability_zone
          )
        end
        # Fill the InventoryCollections with data, that have one new VM and are missing one VM
        %w[1 3].each do |i|
          @persister.vms.build(vm_data(i).merge(:name                  => "vm_changed_name_#{i}",
                                                :availability_zone     => availability_zone,
                                                :ext_management_system => @ems))
        end

        # Invoke the InventoryCollections saving
        InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

        # Assert that saved data have the new VM and miss the deleted VM
        assert_all_records_match_hashes(
          [Vm.all, @ems.vms, availability_zone.vms],
          {:id => @vm1.id, :ems_ref => "vm_ems_ref_1", :name => "vm_changed_name_1", :location => "vm_location_1"},
          {:id => anything, :ems_ref => "vm_ems_ref_3", :name => "vm_changed_name_3", :location => "vm_location_3"}
        )
      end

      it 'deletes missing and creates new VMs with CloudTenant parent' do
        cloud_tenant = FactoryBot.create(:cloud_tenant, :ext_management_system => @ems)
        @vm1.update(:cloud_tenant => cloud_tenant)
        @vm2.update(:cloud_tenant => cloud_tenant)

        # Initialize the InventoryCollections
        @persister.add_collection(:vms) do |builder|
          builder.add_properties(
            :model_class => ManageIQ::Providers::CloudManager::Vm,
            :parent      => cloud_tenant
          )
        end
        # Fill the InventoryCollections with data, that have one new VM and are missing one VM
        %w[1 3].each do |i|
          @persister.vms.build(vm_data(i).merge(:name                  => "vm_changed_name_#{i}",
                                                :cloud_tenant          => cloud_tenant,
                                                :ext_management_system => @ems))
        end

        # Invoke the InventoryCollections saving
        InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

        # Assert that saved data have the new VM and miss the deleted VM
        assert_all_records_match_hashes(
          [Vm.all, @ems.vms, cloud_tenant.vms],
          {:id => @vm1.id, :ems_ref => "vm_ems_ref_1", :name => "vm_changed_name_1", :location => "vm_location_1"},
          {:id => anything, :ems_ref => "vm_ems_ref_3", :name => "vm_changed_name_3", :location => "vm_location_3"}
        )
      end

      it 'affects oly relation to CloudTenant when not providing EMS relation and with CloudTenant parent' do
        cloud_tenant = FactoryBot.create(:cloud_tenant, :ext_management_system => @ems)
        @vm1.update(:cloud_tenant => cloud_tenant)
        @vm2.update(:cloud_tenant => cloud_tenant)

        # Initialize the InventoryCollections
        @persister.add_collection(:vms) do |builder|
          builder.add_properties(
            :model_class => ManageIQ::Providers::CloudManager::Vm,
            :parent      => cloud_tenant
          )
        end

        # Fill the InventoryCollections with data, that have one new VM and are missing one VM
        @persister.vms.build(vm_data(1).merge(:name         => "vm_changed_name_1",
                                              :cloud_tenant => cloud_tenant))

        @persister.vms.build(vm_data(3).merge(:name                  => "vm_changed_name_3",
                                              :cloud_tenant          => cloud_tenant,
                                              :ext_management_system => nil))

        # Invoke the InventoryCollections saving
        InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

        # Assert that saved data have the new VM and miss the deleted VM
        assert_all_records_match_hashes(
          [Vm.all, cloud_tenant.vms],
          {:id => @vm1.id, :ems_ref => "vm_ems_ref_1", :name => "vm_changed_name_1", :location => "vm_location_1"},
          {:id => anything, :ems_ref => "vm_ems_ref_3", :name => "vm_changed_name_3", :location => "vm_location_3"}
        )

        # Assert that ems relation exists only for the updated VM
        assert_all_records_match_hashes(
          [@ems.vms],
          :id => @vm1.id, :ems_ref => "vm_ems_ref_1", :name => "vm_changed_name_1", :location => "vm_location_1"
        )
      end

      it 'does not delete the missing VMs with :complete => false and with CloudTenant parent' do
        cloud_tenant = FactoryBot.create(:cloud_tenant, :ext_management_system => @ems)
        @vm1.update(:cloud_tenant => cloud_tenant)
        @vm2.update(:cloud_tenant => cloud_tenant)

        # Initialize the InventoryCollections
        @persister.add_collection(:vms) do |builder|
          builder.add_properties(
            :model_class => ManageIQ::Providers::CloudManager::Vm,
            :parent      => cloud_tenant,
            :complete    => false
          )
        end

        # Fill the InventoryCollections with data, that have one new VM and are missing one VM
        @persister.vms.build(vm_data(1).merge(:name         => "vm_changed_name_1",
                                              :cloud_tenant => cloud_tenant))

        @persister.vms.build(vm_data(3).merge(:name                  => "vm_changed_name_3",
                                              :cloud_tenant          => cloud_tenant,
                                              :ext_management_system => nil))

        # Invoke the InventoryCollections saving
        InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

        # Assert that saved data have the new VM and miss the deleted VM
        assert_all_records_match_hashes(
          [Vm.all, cloud_tenant.vms],
          {:id => @vm1.id, :ems_ref => "vm_ems_ref_1", :name => "vm_changed_name_1", :location => "vm_location_1"},
          {:id => @vm2.id, :ems_ref => "vm_ems_ref_2", :name => "vm_name_2", :location => "vm_location_2"},
          {:id => anything, :ems_ref => "vm_ems_ref_3", :name => "vm_changed_name_3", :location => "vm_location_3"}
        )

        # Assert that ems relation exists only for the updated VM
        assert_all_records_match_hashes(
          [@ems.vms],
          {:id => @vm1.id, :ems_ref => "vm_ems_ref_1", :name => "vm_changed_name_1", :location => "vm_location_1"},
          {:id => @vm2.id, :ems_ref => "vm_ems_ref_2", :name => "vm_name_2", :location => "vm_location_2"}
        )
      end
    end
  end

  %i[default batch].each do |saver_strategy|
    context "testing reconnect logic with saver_strategy: :#{saver_strategy}" do
      it 'reconnects existing VM' do
        # Fill DB with test Vms
        @vm1 = FactoryBot.create(:vm_cloud, vm_data(1).merge(:ext_management_system => nil))
        @vm2 = FactoryBot.create(:vm_cloud, vm_data(2).merge(:ext_management_system => @ems))

        vms_custom_reconnect_block = lambda do |inventory_collection, inventory_objects_index, attributes_index|
          inventory_objects_index.each_slice(1000) do |batch|
            Vm.where(:ems_ref => batch.map(&:second).map(&:manager_uuid)).each do |record|
              index = inventory_collection.build_stringified_reference_for_record(record, inventory_collection.manager_ref_to_cols)

              # We need to delete the record from the inventory_objects_index and attributes_index, otherwise it
              # would be sent for create.
              inventory_object = inventory_objects_index.delete(index)
              hash = attributes_index.delete(index)

              record.assign_attributes(hash.except(:id, :type))
              if !inventory_collection.check_changed? || record.changed?
                record.save!
                inventory_collection.store_updated_records(record)
              end

              inventory_object.id = record.id
            end
          end
        end

        @persister.add_collection(:vms) do |builder|
          builder.add_properties(
            :model_class            => ManageIQ::Providers::CloudManager::Vm,
            :saver_strategy         => saver_strategy,
            :custom_reconnect_block => vms_custom_reconnect_block
          )
        end
        # Fill the InventoryCollections with data, that have a modified name
        (1..2).each { |i| @persister.vms.build(vm_data(i).merge(:name => "vm_changed_name_#{i}")) }

        # Invoke the InventoryCollections saving
        InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

        # Check the InventoryCollection result matches what was created/deleted/updated
        expect(@persister.vms.created_records).to match_array([])
        expect(@persister.vms.updated_records).to match_array([{:id => @vm1.id}, {:id => @vm2.id}])
        expect(@persister.vms.deleted_records).to match_array([])

        # Assert that saved data have the updated values, checking id to make sure the original records are updated
        assert_all_records_match_hashes(
          [Vm.all, @ems.vms],
          {:id => @vm1.id, :ems_ref => "vm_ems_ref_1", :name => "vm_changed_name_1", :location => "vm_location_1"},
          {:id => @vm2.id, :ems_ref => "vm_ems_ref_2", :name => "vm_changed_name_2", :location => "vm_location_2"}
        )
      end
    end
  end
end
