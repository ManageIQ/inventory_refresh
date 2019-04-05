require_relative '../helpers/test_persister'

describe InventoryRefresh::InventoryCollection::Builder do
  before :each do
    @ems = create_manager
    @persister = create_persister
  end

  def create_manager
    manager = double
    allow(manager).to receive(:id).and_return(1000)
    manager
  end

  def create_persister
    persister_class.new(@ems, InventoryRefresh::TargetCollection.new(:manager => @ems))
  end

  let(:adv_settings) { {:strategy => :local_db_find_missing_references} }

  let(:persister_class) { ::TestPersister }

  # --- association ---

  it 'assigns association automatically to InventoryCollection' do
    ic = described_class.prepare_data(:vms, persister_class).to_inventory_collection

    expect(ic.association).to eq :vms
  end

  # --- model_class ---

  it "derives existing model_class without persister's class" do
    data = described_class.prepare_data(:vms, persister_class).to_hash

    expect(data[:model_class]).to eq ::Vm
  end

  it "replaces derived model_class if model_class defined manually" do
    data = described_class.prepare_data(:vms, persister_class) do |builder|
      builder.add_properties(:model_class => ::MiqTemplate)
    end.to_hash

    expect(data[:model_class]).to eq ::MiqTemplate
  end

  it "doesn't try to derive model_class when disabled" do
    data = described_class.prepare_data(:vms, persister_class, :without_model_class => true).to_hash

    expect(data[:model_class]).to be_nil
  end

  it 'throws exception if model_class not specified' do
    builder = described_class.prepare_data(:non_existing_ic, persister_class)

    expect { builder.to_inventory_collection }.to raise_error(::InventoryRefresh::InventoryCollection::Builder::MissingModelClassError, /NonExistingIc/)
  end

  # --- shared properties ---

  it 'applies shared properties' do
    data = described_class.prepare_data(:tmp, persister_class, :shared_properties => {:update_only => true}).to_hash

    expect(data[:update_only]).to be_truthy
  end

  it "doesn't overwrite defined properties by shared properties" do
    data = described_class.prepare_data(:tmp, persister_class, :shared_properties => {:name => "unknown"}) do |builder|
      builder.add_properties(:name => "my_collection")
    end.to_hash

    expect(data[:name]).to eq "my_collection"
  end

  # --- properties ---

  it 'adds properties with add_properties repeatedly' do
    data = described_class.prepare_data(:tmp, persister_class) do |builder|
      builder.add_properties(:name => "collection", :association => :association_from_parent)
      builder.add_properties(:parent => @ems)
    end.to_hash

    expect(data[:name]).to eq "collection"
    expect(data[:association]).to eq :association_from_parent
    expect(data[:parent]).to eq @ems
  end

  it 'overrides properties in :overwrite mode' do
    data = described_class.prepare_data(:tmp, persister_class) do |builder|
      builder.add_properties(:name => "my_collection")
      builder.add_properties({:name => "other_collection"}, :overwrite)
    end.to_hash

    expect(data[:name]).to eq "other_collection"
  end

  it "doesn't override properties in :if_missing mode" do
    data = described_class.prepare_data(:tmp, persister_class) do |builder|
      builder.add_properties(:name => "my_collection")
      builder.add_properties({:name => "other_collection"}, :if_missing)
    end.to_hash

    expect(data[:name]).to eq "my_collection"
  end

  it 'adds property by method_missing' do
    data = described_class.prepare_data(:tmp, persister_class) do |builder|
      builder.add_manager_ref(:some_foreign_key)
    end.to_hash

    expect(data[:manager_ref]).to eq :some_foreign_key
  end

  it 'raises exception when non existing add_* method called' do
    described_class.prepare_data(:tmp, persister_class) do |builder|
      expect { builder.some_tmp_param(:some_value) }.to raise_exception(NoMethodError)
    end
  end

  it 'raises exception when unallowed property added' do
    message = "InventoryCollection property :bad_property is not allowed. Allowed properties are:\n#{InventoryRefresh::InventoryCollection::Builder.allowed_properties.map(&:to_s).join(', ')}"
    described_class.prepare_data(:tmp, persister_class) do |builder|
      expect { builder.add_properties(:bad_property => :value) }.to raise_exception(message)
    end
  end

  # --- default values ---

  it 'adds default_values repeatedly' do
    data = described_class.prepare_data(:tmp, persister_class) do |builder|
      builder.add_default_values(:ems_id => 10)
      builder.add_default_values(:ems_id => 20)
      builder.add_default_values(:tmp_id => 30)
    end.to_hash

    expect(data[:default_values][:ems_id]).to eq 20
    expect(data[:default_values][:tmp_id]).to eq 30
  end

  # --- dependency attributes ---
  it 'adds dependency_attributes repeatedly' do
    data = described_class.prepare_data(:tmp, persister_class) do |builder|
      builder.add_dependency_attributes(:ic1 => 'ic1')
      builder.add_dependency_attributes(:ic2 => 'ic2', :ic1 => 'ic')
      builder.add_dependency_attributes({ :ic2 => 'ic20_000' }, :if_missing)
    end.to_hash

    expect(data[:dependency_attributes]).to include(:ic1 => 'ic', :ic2 => 'ic2')
  end

  it 'removes dependency_attributes keys' do
    data = described_class.prepare_data(:tmp, persister_class) do |builder|
      builder.add_dependency_attributes(:ic1 => 'ic1', :ic2 => 'ic2', :ic3 => 'ic3')
      builder.remove_dependency_attributes(:ic1)
    end.to_hash
    expect(data[:dependency_attributes]).to include(:ic2 => 'ic2', :ic3 => 'ic3')
    expect(data[:dependency_attributes].key?(:ic1)).to be_falsey
  end

  it 'transforms lambdas' do
    bldr = described_class.prepare_data(:tmp, persister_class) do |builder|
      builder.add_default_values(:ems_id => ->(persister) { persister.manager.id })
      # real values are other inventory_collections, but for this demostration doesn't matter
      builder.add_dependency_attributes(:target => ->(persister) { persister.target })
    end
    bldr.evaluate_lambdas!(@persister)

    data = bldr.to_hash

    expect(data[:default_values][:ems_id]).to eq(@persister.manager.id)
    expect(data[:dependency_attributes][:target]).to be_kind_of(InventoryRefresh::TargetCollection)
  end

  # --- inventory object attributes ---
  it 'derives inventory object attributes automatically' do
    data = described_class.prepare_data(:vms, persister_class).to_hash

    expect(data[:inventory_object_attributes]).not_to be_empty
  end

  it "doesn't derive inventory_object_attributes automatically when disabled" do
    data = described_class.prepare_data(:vms, persister_class, :auto_inventory_attributes => false).to_hash

    expect(data[:inventory_object_attributes]).to be_empty
  end

  it 'can add inventory_object_attributes manually' do
    data = described_class.prepare_data(:tmp, persister_class) do |builder|
      builder.add_inventory_attributes(%i(attr1 attr2 attr3))
    end.to_hash

    expect(data[:inventory_object_attributes]).to match_array(%i(attr1 attr2 attr3))
  end

  it 'can remove inventory_object_attributes' do
    data = described_class.prepare_data(:tmp, persister_class) do |builder|
      builder.add_inventory_attributes(%i(attr1 attr2 attr3))
      builder.remove_inventory_attributes(%i(attr2))
    end.to_hash

    expect(data[:inventory_object_attributes]).to match_array(%i(attr1 attr3))
  end

  it 'can clear all inventory_object_attributes' do
    data = described_class.prepare_data(:vms, persister_class) do |builder|
      builder.add_inventory_attributes(%i(attr1 attr2 attr3))
      builder.clear_inventory_attributes!
    end.to_hash

    expect(data[:inventory_object_attributes]).to be_empty
  end
end
