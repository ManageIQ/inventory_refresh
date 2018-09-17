describe InventoryRefresh::InventoryCollection do
  let(:source)                     { FactoryGirl.create(:ext_management_system) }
  let(:vm)                         { FactoryGirl.create(:vm, :ext_management_system => source) }
  let(:host)                       { FactoryGirl.create(:host, :ext_management_system => source) }
  let(:vms_inventory_collection)   { described_class.new(:model_class => Vm, :parent => source, :association => :vms) }
  let(:hosts_inventory_collection) { described_class.new(:model_class => Host, :parent => source, :association => :hosts) }

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

    context "with two inventory collections" do
      before do
        vms_inventory_collection.build(:ems_ref => vm.ems_ref, :name => vm.name, :host => hosts_inventory_collection.lazy_find(host.ems_ref))
      end

      it "serializes the lazy references" do
        hash = vms_inventory_collection.to_hash
        expect(hash[:data].count).to eq(1)

        vm_data = hash[:data].first
        expect(vm_data[:host]).to include(
          :type                      => "InventoryRefresh::InventoryObjectLazy",
          :inventory_collection_name => :hosts,
          :reference                 => {:ems_ref => host.ems_ref},
          :ref                       => :manager_ref
        )
      end
    end
  end

  context "#from_hash" do
    context "with a single inventory collection" do
      context "with no data" do
        let(:payload) { {:name => :vms, :manager_uuids => [], :all_manager_uuids => nil, :data => [], :partial_data => []} }

        it "deserialized to a valid inventory collection" do
          vms_inventory_collection.from_hash(payload, :vms => vms_inventory_collection)
          expect(vms_inventory_collection.data).to be_empty
        end
      end

      context "with a simple inventory_object" do
        let(:payload) do
          {
            :name              => :vms,
            :manager_uuids     => [],
            :all_manager_uuids => nil,
            :data              => [{:ems_ref => vm.ems_ref, :name => vm.name}],
            :partial_data      => []
          }
        end

        it "deserializes the vm data" do
          vms_inventory_collection.from_hash(payload, :vms => vms_inventory_collection)
          expect(vms_inventory_collection.data.count).to eq(1)
          expect(vms_inventory_collection.data.first.data).to include(:ems_ref => vm.ems_ref, :name => vm.name)
        end
      end
    end

    context "with two inventory collections" do
      let(:payload) do
        {
          :name              => :vms,
          :manager_uuids     => [],
          :all_manager_uuids => nil,
          :data              => [
            {
              :ems_ref => vm.ems_ref,
              :name    => vm.name,
              :host    => {
                :type                        => "InventoryRefresh::InventoryObjectLazy",
                :inventory_collection_name   => :hosts,
                :reference                   => {:ems_ref => host.ems_ref},
                :ref                         => :manager_ref,
                :key                         => nil,
                :default                     => nil,
                :transform_nested_lazy_finds => false
              }
            }
          ],
          :partial_data      => []
        }
      end

      it "deserializes the lazy references" do
        vms_inventory_collection.from_hash(payload, :vms => vms_inventory_collection, :hosts => hosts_inventory_collection)
        expect(vms_inventory_collection.data.count).to eq(1)

        expect(vms_inventory_collection.data.count).to eq(1)

        vm_inv_object = vms_inventory_collection.data.first.data
        expect(vm_inv_object).to include(:ems_ref => vm.ems_ref, :name => vm.name)

        host_lazy_ref = vm_inv_object[:host]
        expect(host_lazy_ref).to                           be_a(InventoryRefresh::InventoryObjectLazy)
        expect(host_lazy_ref.inventory_collection.name).to eq(:hosts)
        expect(host_lazy_ref.stringified_reference).to     eq(host.ems_ref)
      end
    end
  end
end
