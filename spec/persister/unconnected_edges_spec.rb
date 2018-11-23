require_relative '../helpers/spec_mocked_data'
require_relative '../helpers/spec_parsed_data'
require_relative 'targeted_refresh_spec_helper'

describe InventoryRefresh::Persister do
  include SpecMockedData
  include SpecParsedData
  include TargetedRefreshSpecHelper

  ######################################################################################################################
  # Spec scenarios for making sure the skeletal pre-create passes
  ######################################################################################################################

  [
    {}
  ].each do |settings|
    context "with settings #{settings}" do
      before :each do
        @ems = FactoryGirl.create(:ems_container)
      end

      let(:persister) { create_containers_persister }

      it "tests unconnected edges are found" do
        FactoryGirl.create(:container_project, container_project_data(1).merge(:ems_id => @ems.id))
        FactoryGirl.create(:container_project, container_project_data(2).merge(:ems_id => @ems.id))

        persister.container_groups.build(
          container_group_data(
            1,
            :container_project => persister.container_projects.lazy_find(
              {:name => container_project_data(1)[:name]}, {:ref => :by_name}
            ),
          )
        )
        persister.container_groups.build(
          container_group_data(
            2,
            :container_project => persister.container_projects.lazy_find(
              {:name => container_project_data(2)[:name]}, {:ref => :by_name}
            ),
          )
        )
        persister.container_groups.build(
          container_group_data(
            3,
            :container_project => persister.container_projects.lazy_find(
              {:name => container_project_data(3)[:name]}, {:ref => :by_name}
            ),
          )
        )

        persister.container_projects.build(container_project_data(2))

        persister.persist!

        # Assert container_group and container_image are pre-created using the lazy_find data
        assert_containers_counts(
          :container_group   => 3,
          :container_project => 2,
        )

        expect(persister.container_groups.unconnected_edges.size).to eq(1)
        unconnected_edge = persister.container_groups.unconnected_edges.first
        expect(unconnected_edge).to be_a(InventoryRefresh::InventoryCollection::UnconnectedEdge)
        expect(unconnected_edge.inventory_object.ems_ref).to eq(container_group_data(3)[:ems_ref])
        expect(unconnected_edge.inventory_object).to be_a(InventoryRefresh::InventoryObject)
        expect(unconnected_edge.inventory_object_key).to eq(:container_project)
        expect(unconnected_edge.inventory_object_lazy.to_s).to eq(container_project_data(3)[:name])
        expect(unconnected_edge.inventory_object_lazy).to be_a(InventoryRefresh::InventoryObjectLazy)
      end
    end
  end
end
