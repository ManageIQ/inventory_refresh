require_relative "test_collector"
require_relative 'targeted_refresh_spec_helper'
require_relative '../helpers/spec_parsed_data'


describe InventoryRefresh::Persister do
  include TargetedRefreshSpecHelper
  include SpecParsedData

  before(:each) do
    @ems = FactoryGirl.create(:ems_container, :name => "test_ems")
  end

  context "with :retention_strategy => 'archive'" do
    it "automatically fills :last_seen_at timestamp for refreshed entities and archives them in last step" do
      time_now = Time.now.utc
      time_before = Time.now.utc - 20.seconds
      time_after  = Time.now.utc + 20.seconds

      _cg1 = FactoryGirl.create(:container_group, container_group_data(1).merge(:ext_management_system => @ems, :resource_timestamp => time_before))
      _cg2 = FactoryGirl.create(:container_group, container_group_data(2).merge(:ext_management_system => @ems, :resource_timestamp => time_after))
      _cg3 = FactoryGirl.create(:container_group, container_group_data(3).merge(:ext_management_system => @ems, :resource_timestamp => time_now))
      _cg4 = FactoryGirl.create(:container_group, container_group_data(4).merge(:ext_management_system => @ems, :last_seen_at => time_before))
      _cg6 = FactoryGirl.create(:container_group, container_group_data(6).merge(:ext_management_system => @ems, :last_seen_at => time_before))
      _cg7 = FactoryGirl.create(:container_group, container_group_data(7).merge(:ext_management_system => @ems, :last_seen_at => time_before))
      _cn1 = FactoryGirl.create(:container_node, container_node_data(1).merge(:ext_management_system => @ems, :last_seen_at => time_before))
      _cn2 = FactoryGirl.create(:container_node, container_node_data(2).merge(:ext_management_system => @ems))

      refresh_state_uuid = SecureRandom.uuid
      part1_uuid = SecureRandom.uuid
      part2_uuid = SecureRandom.uuid

      # Refresh first part and mark :last_seen_at
      persister = create_containers_persister(:retention_strategy => "archive")
      persister.refresh_state_uuid = refresh_state_uuid
      persister.refresh_state_part_uuid = part1_uuid

      persister.container_groups.build(container_group_data(1).merge(:ext_management_system => @ems, :resource_timestamp => time_before))
      persister.container_groups.build(container_group_data(2).merge(:ext_management_system => @ems, :resource_timestamp => time_before))
      persister.container_groups.build(container_group_data(5).merge(:ext_management_system => @ems, :resource_timestamp => time_before))
      persister.persist!

      # We don't update any records data, but last_seen_at is updated for all records involved
      expect(persister.container_groups.updated_records).to(match_array([]))

      date_field = ContainerGroup.arel_table[:last_seen_at]
      expect(ContainerGroup.where(date_field.gt(time_now)).pluck(:ems_ref)).to(
        match_array([container_group_data(1)[:ems_ref], container_group_data(2)[:ems_ref],
                     container_group_data(5)[:ems_ref]])
      )
      expect(ContainerGroup.where(date_field.lt(time_now)).or(ContainerGroup.where(:last_seen_at => nil)).pluck(:ems_ref)).to(
        match_array([container_group_data(3)[:ems_ref], container_group_data(4)[:ems_ref],
                    container_group_data(6)[:ems_ref], container_group_data(7)[:ems_ref]])
      )

      # Refresh second part and mark :last_seen_at
      persister = create_containers_persister(:retention_strategy => "archive")
      persister.refresh_state_uuid = refresh_state_uuid
      persister.refresh_state_part_uuid = part2_uuid

      persister.container_groups.build(container_group_data(6).merge(:ext_management_system => @ems, :resource_timestamp => time_before))
      persister.persist!

      date_field = ContainerGroup.arel_table[:last_seen_at]
      expect(ContainerGroup.where(date_field.gt(time_now)).pluck(:ems_ref)).to(
        match_array([container_group_data(1)[:ems_ref], container_group_data(2)[:ems_ref],
                     container_group_data(5)[:ems_ref], container_group_data(6)[:ems_ref]])
      )
      expect(ContainerGroup.where(date_field.lt(time_now)).or(ContainerGroup.where(:last_seen_at => nil)).pluck(:ems_ref)).to(
        match_array([container_group_data(3)[:ems_ref], container_group_data(4)[:ems_ref],
                     container_group_data(7)[:ems_ref]])
      )

      # Send persister with total_parts = XY, that will cause sweeping all tables having :last_seen_on column
      persister = create_containers_persister(:retention_strategy => "archive")
      persister.refresh_state_uuid = refresh_state_uuid
      persister.total_parts = 2
      persister.persist!

      expect(ContainerGroup.active.pluck(:ems_ref)).to(
        match_array([container_group_data(1)[:ems_ref], container_group_data(2)[:ems_ref],
                     container_group_data(5)[:ems_ref], container_group_data(6)[:ems_ref]])
      )
      expect(ContainerGroup.archived.pluck(:ems_ref)).to(
        match_array([container_group_data(3)[:ems_ref], container_group_data(4)[:ems_ref],
                     container_group_data(7)[:ems_ref]])
      )

      expect(ContainerNode.active.pluck(:ems_ref)).to(
        match_array([])
      )
      expect(ContainerNode.archived.pluck(:ems_ref)).to(
        match_array([container_node_data(1)[:ems_ref], container_node_data(2)[:ems_ref]])
      )
    end

    it "sweeps only inventory_collections listed in persister's :sweep_scope" do
      time_now = Time.now.utc
      time_before = Time.now.utc - 20.seconds
      time_after  = Time.now.utc + 20.seconds

      _cg1 = FactoryGirl.create(:container_group, container_group_data(1).merge(:ext_management_system => @ems, :resource_timestamp => time_before))
      _cg2 = FactoryGirl.create(:container_group, container_group_data(2).merge(:ext_management_system => @ems, :resource_timestamp => time_after))
      _cg3 = FactoryGirl.create(:container_group, container_group_data(3).merge(:ext_management_system => @ems, :resource_timestamp => time_now))
      _cg4 = FactoryGirl.create(:container_group, container_group_data(4).merge(:ext_management_system => @ems, :last_seen_at => time_before))
      _cg6 = FactoryGirl.create(:container_group, container_group_data(6).merge(:ext_management_system => @ems, :last_seen_at => time_before))
      _cg7 = FactoryGirl.create(:container_group, container_group_data(7).merge(:ext_management_system => @ems, :last_seen_at => time_before))
      _cn1 = FactoryGirl.create(:container_node, container_node_data(1).merge(:ext_management_system => @ems, :last_seen_at => time_before))
      _cn2 = FactoryGirl.create(:container_node, container_node_data(2).merge(:ext_management_system => @ems))

      refresh_state_uuid = SecureRandom.uuid
      part1_uuid = SecureRandom.uuid
      part2_uuid = SecureRandom.uuid

      # Refresh first part and mark :last_seen_at
      persister = create_containers_persister(:retention_strategy => "archive")
      persister.refresh_state_uuid = refresh_state_uuid
      persister.refresh_state_part_uuid = part1_uuid

      persister.container_groups.build(container_group_data(1).merge(:ext_management_system => @ems, :resource_timestamp => time_before))
      persister.container_groups.build(container_group_data(2).merge(:ext_management_system => @ems, :resource_timestamp => time_before))
      persister.container_groups.build(container_group_data(5).merge(:ext_management_system => @ems, :resource_timestamp => time_before))
      persister.persist!

      # Refresh second part and mark :last_seen_at
      persister = create_containers_persister(:retention_strategy => "archive")
      persister.refresh_state_uuid = refresh_state_uuid
      persister.refresh_state_part_uuid = part2_uuid

      persister.container_groups.build(container_group_data(6).merge(:ext_management_system => @ems, :resource_timestamp => time_before))
      persister.persist!

      # Send persister with total_parts = XY, that will cause sweeping all tables having :last_seen_on column
      persister = create_containers_persister(:retention_strategy => "archive")
      persister.refresh_state_uuid = refresh_state_uuid
      persister.total_parts = 2
      persister.sweep_scope = [:container_groups]
      persister.persist!

      expect(ContainerGroup.active.pluck(:ems_ref)).to(
        match_array([container_group_data(1)[:ems_ref], container_group_data(2)[:ems_ref],
                     container_group_data(5)[:ems_ref], container_group_data(6)[:ems_ref]])
      )
      expect(ContainerGroup.archived.pluck(:ems_ref)).to(
        match_array([container_group_data(3)[:ems_ref], container_group_data(4)[:ems_ref],
                     container_group_data(7)[:ems_ref]])
      )

      expect(ContainerNode.active.pluck(:ems_ref)).to(
        match_array([container_node_data(1)[:ems_ref], container_node_data(2)[:ems_ref]])
      )
      expect(ContainerNode.archived.pluck(:ems_ref)).to(
        match_array([])
      )
    end
  end
end
