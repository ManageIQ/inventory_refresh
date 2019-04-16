describe InventoryRefresh::Persister do
  before :each do
    @ems = create_manager
    @persister = described_class.new(@ems)
  end

  def create_manager
    manager = double
    allow(manager).to receive(:id).and_return(1000)
    manager
  end

  context 'InventoryCollection' do
    it 'is created by add_collection' do
      @persister.add_collection(:vms) do |builder|
        builder.add_properties(:model_class => ::Vm)
      end
      expect(@persister.collections[:vms]).to be_kind_of(InventoryRefresh::InventoryCollection)
    end

    it 'is accessible by method_missing' do
      expect(@persister.respond_to?(:vms)).to be_falsey
      expect(@persister.respond_to?(:tmp)).to be_falsey

      @persister.add_collection(:vms)

      expect(@persister.respond_to?(:vms)).to be_truthy
      expect(@persister.vms).to be_kind_of(InventoryRefresh::InventoryCollection)
      expect { @persister.tmp }.to raise_exception(NoMethodError)
    end

    it 'gives correct base columns' do
      @persister.add_collection(:vms)

      expect(@persister.vms.not_null_columns).to(
        match_array(%i(created_on updated_on ems_ref))
      )

      expect(@persister.vms.base_columns).to(
        match_array(%i(ems_id ems_ref created_on updated_on type))
      )
    end
  end
end
