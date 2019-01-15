require_relative 'spec_helper'
require_relative '../helpers/spec_parsed_data'
require_relative '../helpers/test_persister'

describe InventoryRefresh::SaveInventory do
  include SpecHelper
  include SpecParsedData

  ######################################################################################################################
  # Spec scenarios building parent_inventory_collections parameter automatically
  ######################################################################################################################
  #
  before do
    @ems = FactoryBot.create(:ems_cloud,
                              :network_manager => FactoryBot.create(:ems_network))
  end

  let(:persister_class) { ::TestPersister::Cloud }
  let(:persister) { persister_class.new(@ems, @ems) }

  it "checks parent inventory collections defined manually are not overwritten" do
    # Add blank presisters
    persister.add_collection(:vms_and_templates) do |x|
      x.add_properties(:model_class => VmOrTemplate)
    end
    persister.add_collection(:hardwares) do |x|
      x.add_properties(:manager_ref => %i(vm_or_template), :parent_inventory_collections => %i(vms_and_templates))
    end
    persister.add_collection(:disks) do |x|
      x.add_properties(:manager_ref => %i(hardware device_name), :parent_inventory_collections => %i(vms_and_templates))
    end
    persister.add_collection(:networks) do |x|
      x.add_properties(:manager_ref => %i(hardware description), :parent_inventory_collections => %i(vms_and_templates))
    end

    indexed_ics = persister.inventory_collections.index_by(&:name)

    InventoryRefresh::InventoryCollection::Scanner.scan!(persister.inventory_collections)

    # Check parent inventory collections
    expect(indexed_ics[:vms_and_templates].parent_inventory_collections).to be_nil
    expect(indexed_ics[:hardwares].parent_inventory_collections).to(
      match_array([indexed_ics[:vms_and_templates]])
    )
    expect(indexed_ics[:disks].parent_inventory_collections).to(
      match_array([indexed_ics[:vms_and_templates]])
    )
    expect(indexed_ics[:networks].parent_inventory_collections).to(
      match_array([indexed_ics[:vms_and_templates]])
    )

    # Check dependencies
    expect(indexed_ics[:vms_and_templates].dependencies).to eq([])
    expect(indexed_ics[:hardwares].dependencies).to(
      match_array([indexed_ics[:vms_and_templates]])
    )
    expect(indexed_ics[:disks].dependencies).to(
      match_array([indexed_ics[:vms_and_templates]])
    )
    expect(indexed_ics[:networks].dependencies).to(
      match_array([indexed_ics[:vms_and_templates]])
    )
  end

  it "checks parent inventory collections are built correctly based on the model relations" do
    # Add blank presisters
    persister.add_collection(:vms_and_templates) do |x|
      x.add_properties(:model_class => VmOrTemplate)
    end
    persister.add_collection(:hardwares) do |x|
      x.add_properties(:manager_ref => %i(vm_or_template), :parent_inventory_collections => nil)
    end
    persister.add_collection(:disks) do |x|
      x.add_properties(:manager_ref => %i(hardware device_name), :parent_inventory_collections => nil)
    end
    persister.add_collection(:networks) do |x|
      x.add_properties(:manager_ref => %i(hardware description), :parent_inventory_collections => nil)
    end

    indexed_ics = persister.inventory_collections.index_by(&:name)
    expect(indexed_ics[:vms_and_templates].parent_inventory_collections).to be_nil
    expect(indexed_ics[:hardwares].parent_inventory_collections).to be_nil
    expect(indexed_ics[:disks].parent_inventory_collections).to be_nil
    expect(indexed_ics[:networks].parent_inventory_collections).to be_nil

    InventoryRefresh::InventoryCollection::Scanner.scan!(persister.inventory_collections)

    # Check parent inventory collections
    expect(indexed_ics[:vms_and_templates].parent_inventory_collections).to be_nil
    expect(indexed_ics[:hardwares].parent_inventory_collections).to(
      match_array([indexed_ics[:vms_and_templates]])
    )
    expect(indexed_ics[:disks].parent_inventory_collections).to(
      match_array([indexed_ics[:vms_and_templates]])
    )
    expect(indexed_ics[:networks].parent_inventory_collections).to(
      match_array([indexed_ics[:vms_and_templates]])
    )

    # Check dependencies
    expect(indexed_ics[:vms_and_templates].dependencies).to eq([])
    expect(indexed_ics[:hardwares].dependencies).to(
      match_array([indexed_ics[:vms_and_templates]])
    )
    expect(indexed_ics[:disks].dependencies).to(
      match_array([indexed_ics[:hardwares]])
    )
    expect(indexed_ics[:networks].dependencies).to(
      match_array([indexed_ics[:hardwares]])
    )
  end

  it "checks parent inventory collections are not overwritten when set as []" do
    # Add blank presisters
    persister.add_collection(:vms_and_templates) do |x|
      x.add_properties(:model_class => VmOrTemplate, :parent_inventory_collections => [])
    end
    persister.add_collection(:hardwares) do |x|
      x.add_properties(:manager_ref => %i(vm_or_template), :parent_inventory_collections => [])
    end
    persister.add_collection(:disks) do |x|
      x.add_properties(:manager_ref => %i(hardware device_name), :parent_inventory_collections => [])
    end
    persister.add_collection(:networks) do |x|
      x.add_properties(:manager_ref => %i(hardware description), :parent_inventory_collections => [])
    end

    indexed_ics = persister.inventory_collections.index_by(&:name)
    expect(indexed_ics[:vms_and_templates].parent_inventory_collections).to eq([])
    expect(indexed_ics[:hardwares].parent_inventory_collections).to eq([])
    expect(indexed_ics[:disks].parent_inventory_collections).to eq([])
    expect(indexed_ics[:networks].parent_inventory_collections).to eq([])

    InventoryRefresh::InventoryCollection::Scanner.scan!(persister.inventory_collections)

    expect(indexed_ics[:vms_and_templates].parent_inventory_collections).to eq([])
    expect(indexed_ics[:hardwares].parent_inventory_collections).to eq([])
    expect(indexed_ics[:disks].parent_inventory_collections).to eq([])
    expect(indexed_ics[:networks].parent_inventory_collections).to eq([])
  end

  it "checks error is thrown for non-existent inventory collection" do
    persister.add_collection(:hardwares) do |x|
      x.add_properties(:manager_ref => %i(vm_or_template), :parent_inventory_collections => %i(random_name))
    end

    expect { InventoryRefresh::InventoryCollection::Scanner.scan!(persister.inventory_collections) }.to(
      raise_error.with_message(/Can't find InventoryCollection :random_name referenced from/)
    )
  end
end
