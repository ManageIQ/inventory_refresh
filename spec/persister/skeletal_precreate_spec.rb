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

      let(:persister) { create_containers_persister }

      it "tests tag gets precreated with empty but not null value" do
        persister = create_containers_persister

        persister.container_groups.build(container_group_data(1))
        persister.container_group_tags.build(
          :container_group => persister.container_groups.lazy_find(container_group_data(1)[:ems_ref]),
          :tag             => persister.tags.lazy_find(:name => "tag_name_1", :value => '')
        )
        persister.persist!

        # Assert tags are precreated
        assert_containers_counts(
          :container_group      => 1,
          :container_group_tags => 1,
          :tags                 => 1,
        )

        container_group = ContainerGroup.find_by(:ems_ref => container_group_data(1)[:ems_ref])
        expect(container_group).to(
          have_attributes(
            :name    => "container_group_name_1",
            :ems_id  => @ems.id,
            :ems_ref => "container_group_ems_ref_1",
          )
        )
        expect(container_group.container_group_tags.count).to eq 1
        expect(container_group.tags.count).to eq 1
      end

      it "tests tag doesn't get precreated with null value" do
        persister = create_containers_persister

        persister.container_groups.build(container_group_data(1))
        persister.container_group_tags.build(
          :container_group => persister.container_groups.lazy_find(container_group_data(1)[:ems_ref]),
          :tag             => persister.tags.lazy_find(:name => "tag_name_1", :value => nil)
        )

        expect { persister.persist! }.to(
          raise_error(/Referential integrity check violated for/)
        )
      end

      it "tests container relations are pre-created and updated by other refresh" do
        persister = create_containers_persister

        persister.containers.build(
          container_data(
            1,
            :container_group => persister.container_groups.lazy_find("container_group_ems_ref_1"),
            :container_image => persister.container_images.lazy_find("container_image_image_ref_1"),
          )
        )

        persister.persist!

        # Assert container_group and container_image are pre-created using the lazy_find data
        assert_containers_counts(
          :container       => 1,
          :container_group => 1,
          :container_image => 1,
        )

        container = Container.first
        expect(container).to(
          have_attributes(
            :name    => "container_name_1",
            :ems_id  => @ems.id,
            :ems_ref => "container_ems_ref_1",
          )
        )

        expect(container.container_group).to(
          have_attributes(
            :name    => nil,
            :ems_id  => @ems.id,
            :ems_ref => "container_group_ems_ref_1",
          )
        )

        expect(container.container_image).to(
          have_attributes(
            :name      => nil,
            :ems_id    => @ems.id,
            :image_ref => "container_image_image_ref_1",
          )
        )

        expect(container.container_image.container_image_registry).to be_nil

        # Now we persist the relations which should update the skeletal pre-created objects
        persister = create_containers_persister

        persister.container_images.build(
          container_image_data(
            1,
            :container_image_registry => persister.container_image_registries.lazy_find(
              :host => "container_image_registry_host_1",
              :port => "container_image_registry_name_1"
            )
          )
        )

        persister.container_groups.build(container_group_data(1))

        persister.persist!

        # Assert container_group and container_image are updated
        assert_containers_counts(
          :container                => 1,
          :container_group          => 1,
          :container_image          => 1,
          :container_image_registry => 1,
        )

        container = Container.first
        expect(container).to(
          have_attributes(
            :name    => "container_name_1",
            :ems_id  => @ems.id,
            :ems_ref => "container_ems_ref_1",
          )
        )

        expect(container.container_group).to(
          have_attributes(
            :name    => "container_group_name_1",
            :ems_id  => @ems.id,
            :ems_ref => "container_group_ems_ref_1",
          )
        )

        expect(container.container_image).to(
          have_attributes(
            :name      => "container_image_name_1",
            :ems_id    => @ems.id,
            :image_ref => "container_image_image_ref_1",
          )
        )

        expect(container.container_image.container_image_registry).to(
          have_attributes(
            :name => nil,
            :host => "container_image_registry_host_1",
            :port => "container_image_registry_name_1",
          )
        )
      end

      it "tests relations are pre-created but batch strategy doesn't mix full and skeletal records together" do
        FactoryBot.create(:container_project, container_project_data(1).merge(:ems_id => @ems.id))
        FactoryBot.create(:container_project, container_project_data(2).merge(:ems_id => @ems.id))

        persister.container_groups.build(
          container_group_data(
            1,
            :container_project => persister.container_projects.lazy_find("container_project_ems_ref_1"),
          )
        )
        persister.container_projects.build(container_project_data(2))

        persister.persist!

        # Assert container_group and container_image are pre-created using the lazy_find data
        assert_containers_counts(
          :container_group   => 1,
          :container_project => 2,
        )

        # The batch saving must not save full record and skeletal record together, otherwise that would
        # lead to nullifying of all attributes of the existing record, that skeletal record points to.
        expect(ContainerProject.find_by(:ems_ref => "container_project_ems_ref_1")).to(
          have_attributes(
            :name    => "container_project_name_1", # This has to be "container_project_name_1",
            :ems_id  => @ems.id,
            :ems_ref => "container_project_ems_ref_1",
          )
        )
        expect(ContainerProject.find_by(:ems_ref => "container_project_ems_ref_2")).to(
          have_attributes(
            :name    => "container_project_name_2",
            :ems_id  => @ems.id,
            :ems_ref => "container_project_ems_ref_2",
          )
        )
      end

      it "test skeletal precreate doesn't update existing records" do
        # TODO(lsmola) if we set STI subclass inside of the parser, the correct class is not set by skeletal
        # precreate. Is it ok?
        persister.container_groups.instance_variable_set(:@model_class, ContainerGroup)

        persister.containers.build(
          container_data(
            1,
            :container_group => persister.container_groups.lazy_find("container_group_ems_ref_1"),
          )
        )

        persister.persist!

        # We create container and skeletal precreate container_group
        match_created(persister, :container_groups => ContainerGroup.all, :containers => Container.all)
        match_updated(persister)
        match_deleted(persister)

        # Assert container_group and container_image are pre-created using the lazy_find data
        assert_containers_counts(
          :container       => 1,
          :container_group => 1,
        )

        container = Container.first
        expect(container).to(
          have_attributes(
            :name    => "container_name_1",
            :ems_id  => @ems.id,
            :ems_ref => "container_ems_ref_1",
          )
        )

        expect(container.container_group).to(
          have_attributes(
            :type    => "ContainerGroup",
            :name    => nil,
            :ems_id  => @ems.id,
            :ems_ref => "container_group_ems_ref_1",
          )
        )

        # Now we persist the relations which should update the skeletal pre-created objects
        persister = create_containers_persister

        persister.container_groups.build(
          container_group_data(
            1,
            :type => "ContainerGroup"
          )
        )

        persister.persist!

        match_created(persister)
        # We update the skeletal object with full data
        match_updated(persister, :container_groups => ContainerGroup.all)
        match_deleted(persister)

        # Assert container_group and container_image are updated
        assert_containers_counts(
          :container       => 1,
          :container_group => 1,
        )

        container = Container.first
        expect(container).to(
          have_attributes(
            :name    => "container_name_1",
            :ems_id  => @ems.id,
            :ems_ref => "container_ems_ref_1",
          )
        )

        expect(container.container_group).to(
          have_attributes(
            :type    => "ContainerGroup",
            :name    => "container_group_name_1",
            :ems_id  => @ems.id,
            :ems_ref => "container_group_ems_ref_1",
          )
        )

        # Now another skeletal will not update the container group record
        persister = create_containers_persister

        persister.containers.build(
          container_data(
            1,
            :container_group => persister.container_groups.lazy_find("container_group_ems_ref_1"),
          )
        )

        persister.persist!

        match_created(persister)
        # We don't update/create the container group, since skeletal precreate was already done
        match_updated(persister, :containers => Container.all)
        match_deleted(persister)

        # Assert container_group and container_image are pre-created using the lazy_find data
        assert_containers_counts(
          :container       => 1,
          :container_group => 1,
        )

        container = Container.first
        expect(container).to(
          have_attributes(
            :name    => "container_name_1",
            :ems_id  => @ems.id,
            :ems_ref => "container_ems_ref_1",
          )
        )

        expect(container.container_group).to(
          have_attributes(
            :type    => "ContainerGroup",
            :name    => "container_group_name_1",
            :ems_id  => @ems.id,
            :ems_ref => "container_group_ems_ref_1",
          )
        )
      end

      it "we prec-create object that was already disconnected and the relation is filled but not reconnected" do
        FactoryBot.create(:container_project, container_project_data(1).merge(
          :ems_id      => @ems.id,
          :archived_at => Time.now.utc
        ))

        lazy_find_container_project = persister.container_projects.lazy_find("container_project_ems_ref_1")

        persister.container_groups.build(
          container_group_data(
            1,
            :container_project => lazy_find_container_project,
          )
        )

        persister.persist!

        assert_containers_counts(
          :container_group   => 1,
          :container_project => 1,
        )

        container_group = ContainerGroup.first
        expect(container_group).to(
          have_attributes(
            :name    => "container_group_name_1",
            :ems_ref => "container_group_ems_ref_1"
          )
        )

        expect(container_group.container_project).to(
          have_attributes(
            :name    => "container_project_name_1",
            :ems_ref => "container_project_ems_ref_1",
          )
        )
        expect(container_group.container_project).not_to be_nil
      end

      it "lazy_find with secondary ref doesn't pre-create records" do
        lazy_find_container_project = persister.container_projects.lazy_find("container_project_name_1", :ref => :by_name)
        lazy_find_container_node    = persister.container_projects.lazy_find("container_node_name_1", :ref => :by_name)

        persister.container_groups.build(
          container_group_data(
            1,
            :container_project    => lazy_find_container_project,
            :container_node       => lazy_find_container_node,
            :container_replicator => persister.container_replicators.lazy_find(
              {
                :container_project => lazy_find_container_project,
                :name              => "container_replicator_name_1"
              }, {
                :ref => :by_container_project_and_name
              }
            ),
          )
        )

        persister.persist!

        assert_containers_counts(
          :container_group => 1,
        )

        container_group = ContainerGroup.first
        expect(container_group).to(
          have_attributes(
            :name    => "container_group_name_1",
            :ems_id  => @ems.id,
            :ems_ref => "container_group_ems_ref_1",
          )
        )

        expect(container_group.container_project).to be_nil
        expect(container_group.container_node).to be_nil
        expect(container_group.container_replicator).to be_nil
      end

      it "lazy_find with secondary ref doesn't pre-create records but finds them in DB" do
        container_project = FactoryBot.create(:container_project, container_project_data(1).merge(:ems_id => @ems.id))
        FactoryBot.create(:container_node, container_node_data(1).merge(:ems_id => @ems.id))
        FactoryBot.create(:container_replicator, container_replicator_data(1).merge(
                                                    :ems_id            => @ems.id,
                                                    :container_project => container_project
        ))

        lazy_find_container_project = persister.container_projects.lazy_find("container_project_name_1", :ref => :by_name)
        lazy_find_container_node    = persister.container_nodes.lazy_find("container_node_name_1", :ref => :by_name)

        persister.container_groups.build(
          container_group_data(
            1,
            :container_project    => lazy_find_container_project,
            :container_node       => lazy_find_container_node,
            :container_replicator => persister.container_replicators.lazy_find(
              {
                :container_project => lazy_find_container_project,
                :name              => "container_replicator_name_1"
              }, {
                :ref => :by_container_project_and_name
              }
            ),
            :container_build_pod  => persister.container_build_pods.lazy_find(
              :namespace => "container_project_name_1",
              :name      => nil
            )
          )
        )

        persister.persist!

        assert_containers_counts(
          :container_group      => 1,
          :container_project    => 1,
          :container_node       => 1,
          :container_replicator => 1,
        )

        container_group = ContainerGroup.first
        expect(container_group.container_project).to(
          have_attributes(
            :name    => "container_project_name_1",
            :ems_ref => "container_project_ems_ref_1"
          )
        )
        expect(container_group.container_node).to(
          have_attributes(
            :name    => "container_node_name_1",
            :ems_ref => "container_node_ems_ref_1"
          )
        )
        expect(container_group.container_replicator).to(
          have_attributes(
            :name    => "container_replicator_name_1",
            :ems_ref => "container_replicator_ems_ref_1"
          )
        )
        expect(container_group.container_build_pod).to be_nil
      end

      it "lazy_find with secondary ref doesn't pre-create records but finds them in DB, even when disconnected" do
        # TODO(lsmola) we can't find disconnected records using secondary ref now, we should, right?
        FactoryBot.create(:container_project, container_project_data(1).merge(:ems_id => @ems.id, :archived_at => Time.now.utc))
        FactoryBot.create(:container_node, container_node_data(1).merge(:ems_id => @ems.id, :archived_at => Time.now.utc))

        lazy_find_container_project = persister.container_projects.lazy_find("container_project_name_1", :ref => :by_name)
        lazy_find_container_node    = persister.container_projects.lazy_find("container_node_name_1", :ref => :by_name)

        persister.container_groups.build(
          container_group_data(
            1,
            :container_project => lazy_find_container_project,
            :container_node    => lazy_find_container_node,
          )
        )

        persister.persist!

        assert_containers_counts(
          :container_group   => 1,
          :container_project => 1,
          :container_node    => 1,
        )

        container_group = ContainerGroup.first
        # This project is in the DB but disconnected, we want to find it
        expect(container_group.container_project).to be_nil
        expect(container_group.container_node).to be_nil
      end

      it "we reconnect existing container group and reconnect relation by skeletal precreate" do
        FactoryBot.create(:container_group, container_group_data(1).merge(
          :ems_id      => @ems.id,
          :archived_at => Time.now.utc
        ))
        FactoryBot.create(:container_project, container_project_data(1).merge(
          :ems_id      => @ems.id,
          :archived_at => Time.now.utc
        ))

        lazy_find_container_project = persister.container_projects.lazy_find("container_project_ems_ref_1")

        persister.container_groups.build(
          container_group_data(
            1,
            :container_project => lazy_find_container_project,
          )
        )

        persister.persist!

        assert_containers_counts(
          :container_group   => 1,
          :container_project => 1,
        )

        container_group = ContainerGroup.first
        expect(container_group).to(
          have_attributes(
            :name        => "container_group_name_1",
            :ems_ref     => "container_group_ems_ref_1",
            :archived_at => nil
          )
        )

        expect(container_group.container_project).to(
          have_attributes(
            :name    => "container_project_name_1",
            :ems_ref => "container_project_ems_ref_1",
          )
        )
        expect(container_group.container_project.archived_at).not_to be_nil
      end

      it "pre-create doesn't shadow local db strategy" do
        FactoryBot.create(:container_project, container_project_data(1).merge(:ems_id => @ems.id))

        lazy_find_container_project = persister.container_projects.lazy_find("container_project_ems_ref_1")

        persister.container_groups.build(
          container_group_data(
            1,
            :container_project => lazy_find_container_project,
            # This will go from skeletal precreate that fetches it from the DB
            :name              => persister.container_projects.lazy_find("container_project_ems_ref_1", :key => :name)
          )
        )

        persister.persist!

        assert_containers_counts(
          :container_group   => 1,
          :container_project => 1,
        )

        container_group = ContainerGroup.first
        expect(container_group).to(
          have_attributes(
            :name    => "container_project_name_1",
            :ems_ref => "container_group_ems_ref_1"
          )
        )

        expect(container_group.container_project).to(
          have_attributes(
            :name    => "container_project_name_1",
            :ems_ref => "container_project_ems_ref_1"
          )
        )
      end

      it "lazy_find doesn't pre-create records if 1 of the keys is nil" do
        # TODO(lsmola) we should figure out how to safely do that, while avoiding creating bad records, we would have to
        # only call lazy_find with valid combination, which we do not do now.

        persister.container_groups.build(
          container_group_data(
            1,
            :container_build_pod => persister.container_build_pods.lazy_find(
              :namespace => "container_project_name_1",
              :name      => nil
            )
          )
        )

        persister.persist!

        assert_containers_counts(
          :container_group => 1,
        )
      end

      it "lazy_find doesn't pre-create records if :key accessor is used" do
        # TODO(lsmola) right now the :key is not even allowed in lazy_find, once it will be, the skeletal pre-create
        # should not create these
        expect do
          persister.container_groups.build(
            container_group_data(
              1,
              :container_build_pod => persister.container_build_pods.lazy_find(
                :namespace => persister.container_projects.lazy_find("container_project_ems_ref_1", :key => :name),
                :name      => "container_build_pod_name_1"
              )
            )
          )

          persister.persist!

          assert_containers_counts(
            :container_group => 1,
          )
        end.to(raise_error("A lazy_find with a :key can't be a part of the manager_uuid"))
      end
    end
  end
end
