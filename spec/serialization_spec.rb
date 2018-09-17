describe InventoryRefresh::InventoryCollection do
  let(:source)                   { FactoryGirl.create(:ext_management_system) }
  let(:vm)                       { FactoryGirl.create(:vm, :ext_management_system => source) }
  let(:vms_inventory_collection) { described_class.new(:model_class => Vm, :parent => source, :association => :vms) }

  context "#to_hash" do
    context "with a single inventory collection" do
      context "with no data" do
        it "serializes to a valid hash" do
          hash = vms_inventory_collection.to_hash
          expect(hash).to include(:name => :vms, :data => [])
        end
      end

      context "with a simple inventory_object" do
        before do
          vms_inventory_collection.build(:ems_ref => vm.ems_ref, :name => vm.name)
        end

        it "serializes the vm data" do
          hash = vms_inventory_collection.to_hash
          expect(hash[:data]).to include(:ems_ref => vm.ems_ref, :name => vm.name)
        end
      end
    end
  end

  context "#from_hash" do
    context "with a single inventory collection" do
      context "with no data" do
        let(:payload) { {:name=>:vms, :manager_uuids=>[], :all_manager_uuids=>nil, :data=>[], :partial_data=>[]} }

        it "deserialized to a valid inventory collection" do
          vms_inventory_collection.from_hash(payload, {:vms => vms_inventory_collection})
          expect(vms_inventory_collection.data).to be_empty
        end
      end

      context "with a simple inventory_object" do
        let(:payload) { {:name=>:vms, :manager_uuids=>[], :all_manager_uuids=>nil, :data=>[{:ems_ref=>vm.ems_ref, :name=>vm.name}], :partial_data=>[]} }

        it "deserializes the vm data" do
          vms_inventory_collection.from_hash(payload, {:vms => vms_inventory_collection})
          expect(vms_inventory_collection.data.count).to eq(1)
          expect(vms_inventory_collection.data.first.data).to include(:ems_ref => vm.ems_ref, :name => vm.name)
        end
      end
    end
  end
end
