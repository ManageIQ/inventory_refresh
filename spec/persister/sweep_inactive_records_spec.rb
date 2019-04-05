require_relative "test_collector"
require_relative 'targeted_refresh_spec_helper'
require_relative '../helpers/spec_parsed_data'

require "inventory_refresh/null_logger"

describe InventoryRefresh::Persister do
  include TargetedRefreshSpecHelper
  include SpecParsedData

  before(:each) do
    @ems = FactoryBot.create(:ems_container, :name => "test_ems")
  end
  [{:serialize => true}, {:serialize => false}].each do |config|
    context "with config #{config}" do
      context "with :retention_strategy => 'archive'" do
        it "automatically fills :last_seen_at timestamp for refreshed entities and archives them in last step" do
          time_now         = Time.now.utc
          time_before      = Time.now.utc - 20.seconds
          time_more_before = Time.now.utc - 40.seconds
          time_after       = Time.now.utc + 20.seconds

          cg1  = FactoryBot.create(:container_group, container_group_data(1).merge(:ext_management_system => @ems, :resource_timestamp => time_before))
          cg2 = FactoryBot.create(:container_group, container_group_data(2).merge(:ext_management_system => @ems, :resource_timestamp => time_more_before))
          _cg3 = FactoryBot.create(:container_group, container_group_data(3).merge(:ext_management_system => @ems, :resource_timestamp => time_now))
          _cg4 = FactoryBot.create(:container_group, container_group_data(4).merge(:ext_management_system => @ems, :last_seen_at => time_before))
          _cg6 = FactoryBot.create(:container_group, container_group_data(6).merge(:ext_management_system => @ems, :last_seen_at => time_before))
          _cg7 = FactoryBot.create(:container_group, container_group_data(7).merge(:ext_management_system => @ems, :last_seen_at => time_before))
          _cn1 = FactoryBot.create(:container_node, container_node_data(1).merge(:ext_management_system => @ems, :last_seen_at => time_before))
          _cn2 = FactoryBot.create(:container_node, container_node_data(2).merge(:ext_management_system => @ems))

          refresh_state_uuid = SecureRandom.uuid
          part1_uuid         = SecureRandom.uuid
          part2_uuid         = SecureRandom.uuid

          # Refresh first part and mark :last_seen_at
          persister                         = create_containers_persister(:retention_strategy => "archive")
          persister.refresh_state_uuid      = refresh_state_uuid
          persister.refresh_state_part_uuid = part1_uuid

          persister.container_groups.build(container_group_data(1).merge(:resource_timestamp => time_before))
          persister.container_groups.build(container_group_data(2).merge(:resource_timestamp => time_before))
          persister.container_groups.build(container_group_data(5).merge(:resource_timestamp => time_before))
          persister = persist(persister, config)

          # We update just the first record, and last_seen_at is updated for all records involved
          expect(persister.container_groups.updated_records).to(match_array([{:id => cg2.id}]))

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
          persister                         = create_containers_persister(:retention_strategy => "archive")
          persister.refresh_state_uuid      = refresh_state_uuid
          persister.refresh_state_part_uuid = part2_uuid

          persister.container_groups.build(container_group_data(6).merge(:resource_timestamp => time_before))
          persister = persist(persister, config)

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
          # Send persister with total_parts = XY, that will cause sweeping all tables having :last_seen_on column
          persister.sweep_scope = ["container_groups", "container_nodes"]
          sweep(persister, time_now, config)

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
          time_now    = Time.now.utc
          time_before = Time.now.utc - 20.seconds
          time_after  = Time.now.utc + 20.seconds

          _cg1 = FactoryBot.create(:container_group, container_group_data(1).merge(:ext_management_system => @ems, :resource_timestamp => time_before))
          _cg2 = FactoryBot.create(:container_group, container_group_data(2).merge(:ext_management_system => @ems, :resource_timestamp => time_after))
          _cg3 = FactoryBot.create(:container_group, container_group_data(3).merge(:ext_management_system => @ems, :resource_timestamp => time_now))
          _cg4 = FactoryBot.create(:container_group, container_group_data(4).merge(:ext_management_system => @ems, :last_seen_at => time_before))
          _cg6 = FactoryBot.create(:container_group, container_group_data(6).merge(:ext_management_system => @ems, :last_seen_at => time_before))
          _cg7 = FactoryBot.create(:container_group, container_group_data(7).merge(:ext_management_system => @ems, :last_seen_at => time_before))
          _cn1 = FactoryBot.create(:container_node, container_node_data(1).merge(:ext_management_system => @ems, :last_seen_at => time_before))
          _cn2 = FactoryBot.create(:container_node, container_node_data(2).merge(:ext_management_system => @ems))

          refresh_state_uuid = SecureRandom.uuid
          part1_uuid         = SecureRandom.uuid
          part2_uuid         = SecureRandom.uuid

          # Refresh first part and mark :last_seen_at
          persister                         = create_containers_persister(:retention_strategy => "archive")
          persister.refresh_state_uuid      = refresh_state_uuid
          persister.refresh_state_part_uuid = part1_uuid

          persister.container_groups.build(container_group_data(1).merge(:resource_timestamp => time_before))
          persister.container_groups.build(container_group_data(2).merge(:resource_timestamp => time_before))
          persister.container_groups.build(container_group_data(5).merge(:resource_timestamp => time_before))
          persister = persist(persister, config)

          # Refresh second part and mark :last_seen_at
          persister                         = create_containers_persister(:retention_strategy => "archive")
          persister.refresh_state_uuid      = refresh_state_uuid
          persister.refresh_state_part_uuid = part2_uuid

          persister.container_groups.build(container_group_data(6).merge(:resource_timestamp => time_before))
          persister = persist(persister, config)

          # Send persister with total_parts = XY, that will cause sweeping all tables having :last_seen_on column
          persister.sweep_scope = ["container_groups"]
          sweep(persister, time_now, config)

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
          _c1 = FactoryBot.create(
            :nested_container,
            nested_container_data(1).merge(
              :container_group => cg1,
              :last_seen_at    => time_before
            )
          )
          _c2 = FactoryBot.create(
            :nested_container,
            nested_container_data(2).merge(
              :container_group => cg2,
              :last_seen_at    => time_before
            )
          )

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
          persister = persist(persister, config)

          ################################################################################################################
          # Refresh second part
          persister                         = create_persister
          persister.refresh_state_uuid      = refresh_state_uuid
          persister.refresh_state_part_uuid = part2_uuid

          persister.container_groups.build(container_group_data(6).merge(:resource_timestamp => time_before))
          persister = persist(persister, config)

          ################################################################################################################
          # Sweeping step. Send persister with total_parts = XY, that will cause sweeping all tables having :last_seen_on
          # column
          persister             = create_persister
          persister.sweep_scope = ["container_groups"]

          sweep(persister, time_now, config)

          expect(ContainerGroup.active.pluck(:ems_ref)).to(
            match_array([container_group_data(1)[:ems_ref], container_group_data(2)[:ems_ref],
                         container_group_data(5)[:ems_ref], container_group_data(6)[:ems_ref]])
          )
          expect(ContainerGroup.archived.pluck(:ems_ref)).to(
            match_array([container_group_data(3)[:ems_ref], container_group_data(4)[:ems_ref],
                         container_group_data(7)[:ems_ref]])
          )

          expect(NestedContainer.active.pluck(:ems_ref)).to(
            match_array([nested_container_data(1)[:ems_ref], nested_container_data(2)[:ems_ref]])
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
            nested_container_data(
              1,
              :container_group => persister.container_groups.lazy_find("container_group_ems_ref_1"),
            )
          )

          persister = persist(persister, config)

          ################################################################################################################
          # Sweeping step.
          persister             = create_persister
          persister.sweep_scope = ["nested_containers"]

          sweep(persister, time_now, config)

          expect(ContainerGroup.active.pluck(:ems_ref)).to(
            match_array([container_group_data(1)[:ems_ref], container_group_data(2)[:ems_ref],
                         container_group_data(5)[:ems_ref], container_group_data(6)[:ems_ref]])
          )
          expect(ContainerGroup.archived.pluck(:ems_ref)).to(
            match_array([container_group_data(3)[:ems_ref], container_group_data(4)[:ems_ref],
                         container_group_data(7)[:ems_ref]])
          )

          expect(NestedContainer.active.pluck(:ems_ref)).to(
            match_array([nested_container_data(1)[:ems_ref]])
          )
          expect(NestedContainer.archived.pluck(:ems_ref)).to(
            match_array([nested_container_data(2)[:ems_ref]])
          )
        end

        it "tests we can sweep targeted subcollections by a parent scope" do
          time_now    = Time.now.utc
          time_before = Time.now.utc - 20.seconds
          time_after  = Time.now.utc + 20.seconds

          cg1  = FactoryBot.create(:container_group, container_group_data(1).merge(:ext_management_system => @ems, :resource_timestamp => time_before))
          cg2  = FactoryBot.create(:container_group, container_group_data(2).merge(:ext_management_system => @ems, :resource_timestamp => time_after))
          cg3  = FactoryBot.create(:container_group, container_group_data(3).merge(:ext_management_system => @ems, :resource_timestamp => time_now))
          _cg4 = FactoryBot.create(:container_group, container_group_data(4).merge(:ext_management_system => @ems, :last_seen_at => time_before))
          _cg5 = FactoryBot.create(:container_group, container_group_data(5).merge(:ext_management_system => @ems, :last_seen_at => time_before))
          _cg6 = FactoryBot.create(:container_group, container_group_data(6).merge(:ext_management_system => @ems, :last_seen_at => time_before))
          _cg7 = FactoryBot.create(:container_group, container_group_data(7).merge(:ext_management_system => @ems, :last_seen_at => time_before))
          _c1 = FactoryBot.create(
            :nested_container,
            nested_container_data(1).merge(
              :container_group => cg1,
              :last_seen_at    => time_before
            )
          )
          _c2 = FactoryBot.create(
            :nested_container,
            nested_container_data(2).merge(
              :container_group => cg1,
              :last_seen_at    => time_before
            )
          )
          _c3 = FactoryBot.create(
            :nested_container,
            nested_container_data(3).merge(
              :container_group => cg1,
              :last_seen_at    => time_before
            )
          )
          _c4 = FactoryBot.create(
            :nested_container,
            nested_container_data(4).merge(
              :container_group => cg2,
              :last_seen_at    => time_before
            )
          )
          _c5 = FactoryBot.create(
            :nested_container,
            nested_container_data(5).merge(
              :container_group => cg3,
              :last_seen_at    => time_before
            )
          )

          refresh_state_uuid = SecureRandom.uuid
          part1_uuid         = SecureRandom.uuid
          part2_uuid         = SecureRandom.uuid
          ################################################################################################################
          # Refresh first part

          persister                         = create_persister
          persister.refresh_state_uuid      = refresh_state_uuid
          persister.refresh_state_part_uuid = part1_uuid

          persister.container_groups.build(container_group_data(1).merge(:resource_timestamp => time_before))
          persister.container_groups.build(container_group_data(2).merge(:resource_timestamp => time_before))
          persister.nested_containers.build(
            nested_container_data(
              1,
              :container_group => persister.container_groups.lazy_find("container_group_ems_ref_1"),
            )
          )

          persister = persist(persister, config)

          ################################################################################################################
          # Refresh second part
          persister                         = create_persister
          persister.refresh_state_uuid      = refresh_state_uuid
          persister.refresh_state_part_uuid = part2_uuid

          persister.nested_containers.build(
            nested_container_data(
              2,
              :container_group => persister.container_groups.lazy_find("container_group_ems_ref_1"),
            )
          )

          persister = persist(persister, config)

          ################################################################################################################
          # Sweeping step. Send persister with total_parts = XY, that will cause sweeping all tables having :last_seen_on
          # column
          persister             = create_persister
          persister.sweep_scope = {
            :container_groups  => [
              {:ems_ref => "container_group_ems_ref_1"},
              {:ems_ref => "container_group_ems_ref_2"},
              {:ems_ref => "container_group_ems_ref_3"}
            ],
            :nested_containers => [
              {:container_group => persister.container_groups.lazy_find("container_group_ems_ref_1")},
              {:container_group => persister.container_groups.lazy_find("container_group_ems_ref_2")}
            ]
          }

          sweep(persister, time_now, config)

          expect(ContainerGroup.active.pluck(:ems_ref)).to(
            match_array([container_group_data(1)[:ems_ref], container_group_data(2)[:ems_ref],
                         container_group_data(5)[:ems_ref], container_group_data(6)[:ems_ref],
                         container_group_data(4)[:ems_ref], container_group_data(7)[:ems_ref]])
          )
          expect(ContainerGroup.archived.pluck(:ems_ref)).to(
            match_array([container_group_data(3)[:ems_ref]])
          )

          expect(NestedContainer.active.pluck(:ems_ref)).to(
            match_array([nested_container_data(1)[:ems_ref], nested_container_data(2)[:ems_ref], nested_container_data(5)[:ems_ref]])
          )
          expect(NestedContainer.archived.pluck(:ems_ref)).to(
            match_array([nested_container_data(3)[:ems_ref], nested_container_data(4)[:ems_ref]])
          )
        end
      end

      context "test various scope combinations" do
        let(:time_now) { Time.now.utc }
        let(:time_before) { Time.now.utc - 20.seconds }
        let(:time_after) { Time.now.utc + 20.seconds }

        before :each do
          cg1  = FactoryBot.create(:container_group, container_group_data(1).merge(:ext_management_system => @ems, :last_seen_at => time_now))
          cg2  = FactoryBot.create(:container_group, container_group_data(2).merge(:ext_management_system => @ems, :last_seen_at => time_after))
          cg3  = FactoryBot.create(:container_group, container_group_data(3).merge(:ext_management_system => @ems, :last_seen_at => time_now))
          _cg4 = FactoryBot.create(:container_group, container_group_data(4).merge(:ext_management_system => @ems, :last_seen_at => time_before))
          _cg5 = FactoryBot.create(:container_group, container_group_data(5).merge(:ext_management_system => @ems, :last_seen_at => time_before))
          _cg6 = FactoryBot.create(:container_group, container_group_data(6).merge(:ext_management_system => @ems, :last_seen_at => time_before))
          _cg7 = FactoryBot.create(:container_group, container_group_data(7).merge(:ext_management_system => @ems, :last_seen_at => time_before))
          _c1 = FactoryBot.create(
            :nested_container,
            nested_container_data(1).merge(
              :container_group => cg1,
              :last_seen_at    => time_before
            )
          )
          _c2 = FactoryBot.create(
            :nested_container,
            nested_container_data(2).merge(
              :container_group => cg1,
              :last_seen_at    => time_now
            )
          )
          _c3 = FactoryBot.create(
            :nested_container,
            nested_container_data(3).merge(
              :container_group => cg1,
              :last_seen_at    => time_after
            )
          )
          _c4 = FactoryBot.create(
            :nested_container, nested_container_data(4).merge(
                                 :container_group => cg2,
                                 :last_seen_at    => time_now
                               )
          )
          _c5 = FactoryBot.create(
            :nested_container,
            nested_container_data(5).merge(
              :container_group => cg3,
              :last_seen_at    => time_now
            )
          )
        end

        it "throws error on non existing scope key" do
          persister             = create_persister
          persister.sweep_scope = {
            :container_groups => [
              {:ems_refs => "container_group_ems_ref_1"},
              {:ems_refs => "container_group_ems_ref_2"},
              {:ems_refs => "container_group_ems_ref_3"}
            ]
          }

          expect do
            sweep(persister, time_now, config)
          end.to(
            raise_error(
              InventoryRefresh::Exception::SweeperNonExistentScopeKeyFoundError,
              /contained keys that are not columns: \[:ems_refs\]/
            )
          )
        end

        it "throws error on having non uniform keys" do
          persister             = create_persister
          persister.sweep_scope = {
            :container_groups => [
              {:ems_ref => "container_group_ems_ref_1"},
              {:ems_ref => "container_group_ems_ref_2", :name => "container_group_name_1"},
              {:ems_ref => "container_group_ems_ref_3"}
            ]
          }

          expect do
            sweep(persister, time_now, config)
          end.to(
            raise_error(
              InventoryRefresh::Exception::SweeperNonUniformScopeKeyFoundError,
              /Missing keys for a scope were: \[:name\]/
            )
          )
        end
      end

      def create_persister
        create_containers_persister(:retention_strategy => "archive")
      end

      def persist(persister, config)
        if config[:serialize]
          persister = persister.class.from_json(persister.to_json, @ems)
          persister.persist!
        else
          persister.persist!
        end
        persister
      end

      def sweep(persister, time, config)
        if config[:serialize]
          persister = persister.class.from_json(persister.to_json, @ems)

          InventoryRefresh::SaveInventory.sweep_inactive_records(
            persister.manager,
            persister.inventory_collections,
            persister.sweep_scope,
            refresh_state(2, time, persister.sweep_scope)
          )
        else
          InventoryRefresh::SaveInventory.sweep_inactive_records(
            persister.manager,
            persister.inventory_collections,
            persister.sweep_scope,
            refresh_state(2, time, persister.sweep_scope)
          )
        end
      end

      def refresh_state(total_parts, created_at, sweep_scope = nil)
        state = double(:refresh_state)
        allow(state).to receive(:total_parts).and_return(total_parts)
        allow(state).to receive(:sweep_scope).and_return(sweep_scope)
        allow(state).to receive(:created_at).and_return(created_at)
        state
      end
    end
  end
end
