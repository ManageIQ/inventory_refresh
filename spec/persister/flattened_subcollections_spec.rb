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
        @ems = FactoryBot.create(:ems_container)
      end

      it "tests containers subcollection gets archived by it's own scope" do
        time_now    = Time.now.utc
        time_before = Time.now.utc - 20.seconds
        time_after  = Time.now.utc + 20.seconds

        cg1  = FactoryBot.create(:container_group, container_group_data(1).merge(:ext_management_system => @ems, :resource_timestamp => time_before))
        cg2  = FactoryBot.create(:container_group, container_group_data(2).merge(:ext_management_system => @ems, :resource_timestamp => time_after))
        _cg3 = FactoryBot.create(:container_group, container_group_data(3).merge(:ext_management_system => @ems, :resource_timestamp => time_now))
        _cg4 = FactoryBot.create(:container_group, container_group_data(4).merge(:ext_management_system => @ems, :last_seen_at => time_before))
        _cg6 = FactoryBot.create(:container_group, container_group_data(6).merge(:ext_management_system => @ems, :last_seen_at => time_before))
        _cg7 = FactoryBot.create(:container_group, container_group_data(7).merge(:ext_management_system => @ems, :last_seen_at => time_before))
        _c1  = FactoryBot.create(:nested_container, nested_container_data(1).merge(
          :container_group => cg1,
          :last_seen_at    => time_before
        ))
        _c2  = FactoryBot.create(:nested_container, nested_container_data(2).merge(
          :container_group => cg2,
          :last_seen_at    => time_before
        ))

        ################################################################################################################
        # Refresh first part
        refresh_state_uuid = SecureRandom.uuid
        part1_uuid         = SecureRandom.uuid
        part2_uuid         = SecureRandom.uuid

        # Refresh first part and mark :last_seen_at
        persister                         = create_persister
        persister.refresh_state_uuid      = refresh_state_uuid
        persister.refresh_state_part_uuid = part1_uuid

        persister.container_groups.build(container_group_data(1).merge(:resource_timestamp => time_before))
        persister.container_groups.build(container_group_data(2).merge(:resource_timestamp => time_before))
        persister.container_groups.build(container_group_data(5).merge(:resource_timestamp => time_before))
        persister.persist!

        ################################################################################################################
        # Refresh second part
        persister                         = create_persister
        persister.refresh_state_uuid      = refresh_state_uuid
        persister.refresh_state_part_uuid = part2_uuid

        persister.container_groups.build(container_group_data(6).merge(:ext_management_system => @ems, :resource_timestamp => time_before))
        persister.persist!

        ################################################################################################################
        # Sweeping step. Send persister with total_parts = XY, that will cause sweeping all tables having :last_seen_on
        # column
        persister = create_persister
        InventoryRefresh::SaveInventory.sweep_inactive_records(
          persister.manager,
          persister.inventory_collections,
          refresh_state(2, time_now, ["container_groups"])
        )

        expect(ContainerGroup.active.pluck(:ems_ref)).to(
          match_array([container_group_data(1)[:ems_ref], container_group_data(2)[:ems_ref],
                       container_group_data(5)[:ems_ref], container_group_data(6)[:ems_ref]])
        )
        expect(ContainerGroup.archived.pluck(:ems_ref)).to(
          match_array([container_group_data(3)[:ems_ref], container_group_data(4)[:ems_ref],
                       container_group_data(7)[:ems_ref]])
        )

        expect(NestedContainer.active.pluck(:ems_ref)).to(
          match_array([container_data(1)[:ems_ref], container_data(2)[:ems_ref]])
        )
        expect(NestedContainer.archived.pluck(:ems_ref)).to(
          match_array([])
        )

        ################################################################################################################
        # Refresh third part, refreshing nested containers
        refresh_state_uuid = SecureRandom.uuid
        part1_uuid         = SecureRandom.uuid
        # part2_uuid         = SecureRandom.uuid

        # Refresh first part and mark :last_seen_at
        persister                         = create_persister
        persister.refresh_state_uuid      = refresh_state_uuid
        persister.refresh_state_part_uuid = part1_uuid

        persister.nested_containers.build(
          container_data(
            1,
            :container_group => persister.container_groups.lazy_find("container_group_ems_ref_1"),
          )
        )

        persister.persist!

        ################################################################################################################
        # Sweeping step.
        persister = create_persister
        InventoryRefresh::SaveInventory.sweep_inactive_records(
          persister.manager,
          persister.inventory_collections,
          refresh_state(2, time_now, ["nested_containers"])
        )

        expect(ContainerGroup.active.pluck(:ems_ref)).to(
          match_array([container_group_data(1)[:ems_ref], container_group_data(2)[:ems_ref],
                       container_group_data(5)[:ems_ref], container_group_data(6)[:ems_ref]])
        )
        expect(ContainerGroup.archived.pluck(:ems_ref)).to(
          match_array([container_group_data(3)[:ems_ref], container_group_data(4)[:ems_ref],
                       container_group_data(7)[:ems_ref]])
        )

        expect(NestedContainer.active.pluck(:ems_ref)).to(
          match_array([container_data(1)[:ems_ref]])
        )
        expect(NestedContainer.archived.pluck(:ems_ref)).to(
          match_array([container_data(2)[:ems_ref]])
        )
      end
    end
  end

  def create_persister
    create_containers_persister(:retention_strategy => "archive", :parent_inventory_collections => [])
  end

  def refresh_state(total_parts, created_at, sweep_scope = nil)
    state = double(:refresh_state)
    allow(state).to receive(:total_parts).and_return(total_parts)
    allow(state).to receive(:sweep_scope).and_return(sweep_scope)
    allow(state).to receive(:created_at).and_return(created_at)
    state
  end
end
