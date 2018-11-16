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
    it "archives data with all_manager_uuids_timestamp" do
      persister = create_containers_persister(:retention_strategy => "archive")

      time_now    = Time.now.utc
      time_before = Time.now.utc - 20.seconds
      time_after  = Time.now.utc + 20.seconds

      cg1  = FactoryGirl.create(:container_group, container_group_data(1).merge(:ext_management_system => @ems, :resource_timestamp => time_before))
      _cg2 = FactoryGirl.create(:container_group, container_group_data(2).merge(:ext_management_system => @ems, :resource_timestamp => time_before))
      cg3  = FactoryGirl.create(:container_group, container_group_data(3).merge(:ext_management_system => @ems, :resource_timestamp => time_now))
      _cg4 = FactoryGirl.create(:container_group, container_group_data(4).merge(:ext_management_system => @ems, :resource_timestamp => time_now))
      # This VM was added after we've fetched all possible VMs (e.g. by targeted refresh), so we shouldn't delete it
      _cg5 = FactoryGirl.create(:container_group, container_group_data(5).merge(:ext_management_system => @ems, :resource_timestamp => time_after))

      persister.container_groups.all_manager_uuids = [{'ems_ref' => cg1.ems_ref}, {'ems_ref' => cg3.ems_ref}]
      persister.container_groups.all_manager_uuids_timestamp = time_now.to_s

      persister.persist!

      expect(ContainerGroup.active.pluck(:ems_ref)).to(
        match_array([container_group_data(1)[:ems_ref], container_group_data(3)[:ems_ref],
                     container_group_data(5)[:ems_ref], container_group_data(4)[:ems_ref]])
      )
      expect(ContainerGroup.archived.pluck(:ems_ref)).to(
        match_array([container_group_data(2)[:ems_ref]])
      )
    end

    it "archives nested data with all_manager_uuids_timestamp" do
      time_now    = Time.now.utc
      time_before = Time.now.utc - 20.seconds
      time_after  = Time.now.utc + 20.seconds

      cg1 = FactoryGirl.create(:container_group, container_group_data(1).merge(:ext_management_system => @ems, :resource_timestamp => time_now))
      cg2 = FactoryGirl.create(:container_group, container_group_data(2).merge(:ext_management_system => @ems, :resource_timestamp => time_now))
      _c11 = FactoryGirl.create(:nested_container, nested_container_data(11).merge(:container_group => cg1, :resource_timestamp => time_now))
      _c12 = FactoryGirl.create(:nested_container, nested_container_data(12).merge(:container_group => cg1, :resource_timestamp => time_now))
      _c21 = FactoryGirl.create(:nested_container, nested_container_data(21).merge(:container_group => cg2, :resource_timestamp => time_now))
      _c22 = FactoryGirl.create(:nested_container, nested_container_data(22).merge(:container_group => cg2, :resource_timestamp => time_now))

      # We are sending older data, that should not cause any archival, but we should create the non existent old data
      # nested_container_data(13) and archive them. And we are also sending new data.
      persister = create_containers_persister(:retention_strategy => "archive")
      persister.container_groups.build(container_group_data(1).merge(:resource_timestamp => time_before))
      persister.nested_containers.build(
        nested_container_data(11).merge(
          :container_group    => persister.container_groups.lazy_find(container_group_data(1)[:ems_ref]),
          :resource_timestamp => time_before
        )
      )
      persister.nested_containers.build(
        nested_container_data(13).merge(
          :container_group    => persister.container_groups.lazy_find(container_group_data(1)[:ems_ref]),
          :resource_timestamp => time_before
        )
      )
      persister.container_groups.build(container_group_data(2).merge(:resource_timestamp => time_before))
      persister.nested_containers.build(
        nested_container_data(21).merge(
          :container_group    => persister.container_groups.lazy_find(container_group_data(2)[:ems_ref]),
          :resource_timestamp => time_after
        )
      )
      persister.nested_containers.build(
        nested_container_data(23).merge(
          :container_group    => persister.container_groups.lazy_find(container_group_data(2)[:ems_ref]),
          :resource_timestamp => time_after
        )
      )

      persister.persist!

      expect(ContainerGroup.active.pluck(:ems_ref)).to(
        match_array([container_group_data(1)[:ems_ref], container_group_data(2)[:ems_ref]])
      )
      expect(ContainerGroup.archived.pluck(:ems_ref)).to(
        match_array([])
      )

      expect(NestedContainer.active.pluck(:ems_ref)).to(
        match_array([nested_container_data(11)[:ems_ref], nested_container_data(13)[:ems_ref],
                     nested_container_data(21)[:ems_ref], nested_container_data(23)[:ems_ref]])
      )
      expect(NestedContainer.archived.pluck(:ems_ref)).to(
        match_array([nested_container_data(12)[:ems_ref], nested_container_data(22)[:ems_ref]])
      )
      # TODO(lsmola) This should be the right thing, but there is no way to enforce ensure this now, we test that next
      # refresh will fix it, archiving nested container 13 and reconnecting 12.
      #
      # expect(NestedContainer.active.pluck(:ems_ref)).to(
      #   match_array([nested_container_data(11)[:ems_ref], nested_container_data(12)[:ems_ref],
      #                nested_container_data(21)[:ems_ref], nested_container_data(23)[:ems_ref]])
      # )
      # expect(NestedContainer.archived.pluck(:ems_ref)).to(
      #   match_array([nested_container_data(13)[:ems_ref], , nested_container_data(22)[:ems_ref]])
      # )

      # We are sending newer data
      persister = create_containers_persister(:retention_strategy => "archive")
      persister.container_groups.build(container_group_data(1).merge(:resource_timestamp => time_after))
      persister.nested_containers.build(
        nested_container_data(11).merge(
          :container_group    => persister.container_groups.lazy_find(container_group_data(1)[:ems_ref]),
          :resource_timestamp => time_after
        )
      )
      persister.nested_containers.build(
        nested_container_data(12).merge(
          :container_group    => persister.container_groups.lazy_find(container_group_data(1)[:ems_ref]),
          :resource_timestamp => time_after
        )
      )

      persister.persist!

      expect(ContainerGroup.active.pluck(:ems_ref)).to(
        match_array([container_group_data(1)[:ems_ref], container_group_data(2)[:ems_ref]])
      )
      expect(ContainerGroup.archived.pluck(:ems_ref)).to(
        match_array([])
      )

      expect(NestedContainer.active.pluck(:ems_ref)).to(
        match_array([nested_container_data(11)[:ems_ref], nested_container_data(12)[:ems_ref],
                     nested_container_data(21)[:ems_ref], nested_container_data(23)[:ems_ref]])
      )
      expect(NestedContainer.archived.pluck(:ems_ref)).to(
        match_array([nested_container_data(13)[:ems_ref], nested_container_data(22)[:ems_ref]])
      )
    end
  end

  [{
    :upsert_only            => true,
    :parallel_saving_column => "resource_counter",
  }, {
    :upsert_only            => false,
    :parallel_saving_column => "resource_counter",
  }, {
    :upsert_only            => true,
    :parallel_saving_column => "resource_timestamp",
  }, {
    :upsert_only            => false,
    :parallel_saving_column => "resource_timestamp",
  },].each do |settings|
    context "with settings #{settings}" do
      before(:each) do
        if settings[:upsert_only]
          # This is not real advanced setting. We are forcing DB to return [], which will lead to doing only upsert
          # queries. So this simulates 2 processes writing the same records.
          allow_any_instance_of(@ems.class).to receive(:container_groups).and_return(ContainerGroup.none)
        end
      end

      it "checks the full row saving with the same versions" do
        container_group_created_on = nil

        2.times do |i|
          persister = TestCollector.refresh(
            TestCollector.generate_batches_of_full_container_group_data(
              :settings => settings,
              :ems_name => @ems.name,
              :version  => newest_version(settings),
            )
          )

          ContainerGroup.find_each.each do |container_group|
            expected_version = expected_version(settings, container_group, newest_version(settings))

            expect(container_group).to(
              have_attributes(
                :name                      => "container_group_#{expected_version}",
                version_col(settings)      => expected_version,
                versions_max_col(settings) => nil,
                versions_col(settings)     => {},
                :reason                    => expected_version.to_s,
                :phase                     => "#{expected_version} status",
              )
            )
          end

          if i == 0
            match_created(persister, :container_groups => ContainerGroup.all)
          else
            match_created(persister)
          end
          match_updated(persister)
          match_deleted(persister)
        end

        # Expect the second+ run with same version for each record doesn't change rails versions (the row should
        # not be updated)
        container_group_current_created_on = ContainerGroup.where(:dns_policy => "1").first.created_on
        container_group_created_on ||= container_group_current_created_on
        expect(container_group_created_on).to eq(container_group_current_created_on)
      end

      it "checks the full row saving with increasing versions" do
        bigger_newest_version = newest_version(settings)

        2.times do |i|
          persister = TestCollector.refresh(
            TestCollector.generate_batches_of_full_container_group_data(
              :settings => settings,
              :ems_name => @ems.name,
              :version  => bigger_newest_version,
            )
          )

          ContainerGroup.find_each.each do |container_group|
            expected_version = expected_version(settings, container_group, bigger_newest_version)

            expect(container_group).to(
              have_attributes(
                :name                      => "container_group_#{expected_version}",
                version_col(settings)      => expected_version,
                versions_max_col(settings) => nil,
                versions_col(settings)     => {},
                :reason                    => expected_version.to_s,
                :phase                     => "#{expected_version} status",
              )
            )
          end

          if i == 0
            match_created(persister, :container_groups => ContainerGroup.all)
            match_updated(persister)
          else
            match_created(persister)
            match_updated(persister, :container_groups => ContainerGroup.all)
          end
          match_deleted(persister)

          bigger_newest_version += 10
        end
      end

      it "checks the full row saving with increasing versions but constant resource_version" do
        bigger_newest_version = newest_version(settings)

        2.times do |i|
          persister = TestCollector.refresh(
            TestCollector.generate_batches_of_full_container_group_data(
              :settings         => settings,
              :ems_name         => @ems.name,
              :version          => bigger_newest_version,
              :resource_version => "same_version",
            )
          )

          ContainerGroup.find_each.each do |container_group|
            expected_version = if settings[:upsert_only]
                                 # TODO(lsmola) we should be able to process this also for upsert only, right now we
                                 # just optimize the updating path, so if we would upsert 2 same records in parallel,
                                 # we would not check the resource timestamp.
                                 #
                                 # If we will check it we fail to save full row, then we skeletalize it and save it in
                                 # chunks, the timestamp is bigger, so it leads to saving it. So we need to somehow
                                 # prevent skeletalization in this case. Probably by loading the records by
                                 # map_ids_to_inventory_objects and checking if those should be skeletalized.
                                 expected_version(settings, container_group, bigger_newest_version)
                               else
                                 expected_version(settings, container_group, newest_version(settings))
                               end

            expect(container_group).to(
              have_attributes(
                :name                      => "container_group_#{expected_version}",
                version_col(settings)      => expected_version,
                versions_max_col(settings) => nil,
                versions_col(settings)     => {},
                :reason                    => expected_version.to_s,
                :phase                     => "#{expected_version} status",
              )
            )
          end

          if i == 0
            match_created(persister, :container_groups => ContainerGroup.all)
            match_updated(persister)
          else
            # No changes because resource version is the same
            match_created(persister)

            if settings[:upsert_only]
              match_updated(persister, :container_groups => ContainerGroup.all)
            else
              match_updated(persister)
            end
          end
          match_deleted(persister)

          bigger_newest_version += 10
        end
      end

      it "checks the full row saving with increasing versions and changing resource_version" do
        bigger_newest_version = newest_version(settings)

        2.times do |i|
          persister = TestCollector.refresh(
            TestCollector.generate_batches_of_full_container_group_data(
              :settings         => settings,
              :ems_name         => @ems.name,
              :version          => bigger_newest_version,
              :resource_version => "different_version_#{i}",
            )
          )

          ContainerGroup.find_each.each do |container_group|
            expected_version = expected_version(settings, container_group, bigger_newest_version)

            expect(container_group).to(
              have_attributes(
                :name                      => "container_group_#{expected_version}",
                version_col(settings)      => expected_version,
                versions_max_col(settings) => nil,
                versions_col(settings)     => {},
                :reason                    => expected_version.to_s,
                :phase                     => "#{expected_version} status",
              )
            )
          end

          if i == 0
            match_created(persister, :container_groups => ContainerGroup.all)
            match_updated(persister)
          else
            # No changes because resource version is the same
            match_created(persister)
            match_updated(persister, :container_groups => ContainerGroup.all)
          end
          match_deleted(persister)

          bigger_newest_version += 10
        end
      end

      it "checks the partial rows saving with the same versions" do
        container_group_created_on = nil

        2.times do |i|
          persister = TestCollector.refresh(
            TestCollector.generate_batches_of_partial_container_group_data(
              :settings => settings,
              :ems_name => @ems.name,
              :version  => newest_version(settings),
            )
          )

          ContainerGroup.find_each do |container_group|
            expected_version = expected_version(settings, container_group, newest_version(settings))

            expect(container_group).to(
              have_attributes(
                :name                      => nil,
                version_col(settings)      => nil,
                versions_max_col(settings) => expected_version,
                :reason                    => expected_version.to_s,
                :phase                     => "#{expected_version} status",
              )
            )
            expect(container_group.send(versions_col(settings))).to(
              match(
                "phase"      => expected_version,
                "dns_policy" => expected_version,
                "reason"     => expected_version,
              )
            )
          end

          # Expect the second+ run with same version for each record doesn't change rails versions (the row should
          # not be updated)
          container_group_current_created_on = ContainerGroup.where(:dns_policy => "1").first.created_on
          container_group_created_on ||= container_group_current_created_on
          expect(container_group_created_on).to eq(container_group_current_created_on)

          if i == 0
            match_created(persister, :container_groups => ContainerGroup.all)
          else
            match_created(persister)
          end
          match_updated(persister)
          match_deleted(persister)
        end
      end

      it "check full then partial with the same version" do
        container_group_created_on = nil

        2.times do |i|
          persister = TestCollector.refresh(
            TestCollector.generate_batches_of_full_container_group_data(
              :settings => settings,
              :ems_name => @ems.name,
              :version  => newest_version(settings),
            )
          )

          # Expect the second+ run with same version for each record doesn't change rails versions (the row should
          # not be updated)
          container_group_created_on = ContainerGroup.where(:dns_policy => "1").first.created_on

          if i == 0
            match_created(persister, :container_groups => ContainerGroup.all)
          else
            match_created(persister)
          end
          match_updated(persister)
          match_deleted(persister)
        end

        2.times do
          persister = TestCollector.refresh(
            TestCollector.generate_batches_of_partial_container_group_data(
              :settings => settings,
              :ems_name => @ems.name,
              :version  => newest_version(settings),
            )
          )

          ContainerGroup.find_each do |container_group|
            expected_version = expected_version(settings, container_group, newest_version(settings))

            expect(container_group).to(
              have_attributes(
                :name                      => "container_group_#{expected_version}",
                version_col(settings)      => expected_version,
                versions_max_col(settings) => nil,
                versions_col(settings)     => {},
                :reason                    => expected_version.to_s,
                :phase                     => "#{expected_version} status",
              )
            )
          end

          # Expect the second+ run with same version for each record doesn't change rails versions (the row should
          # not be updated)
          container_group_current_created_on = ContainerGroup.where(:dns_policy => "1").first.created_on
          expect(container_group_created_on).to eq(container_group_current_created_on)

          match_created(persister)
          match_updated(persister)
          match_deleted(persister)
        end
      end

      it "check partial then full with the same version" do
        2.times do |i|
          persister = TestCollector.refresh(
            TestCollector.generate_batches_of_partial_container_group_data(
              :settings => settings,
              :ems_name => @ems.name,
              :version  => newest_version(settings),
            )
          )

          ContainerGroup.find_each do |container_group|
            expected_version = expected_version(settings, container_group, newest_version(settings))

            expect(container_group).to(
              have_attributes(
                :name                      => nil,
                version_col(settings)      => nil,
                versions_max_col(settings) => expected_version,
                :reason                    => expected_version.to_s,
                :phase                     => "#{expected_version} status",
              )
            )

            expect(container_group.send(versions_col(settings))).to(
              match(
                "phase"      => expected_version,
                "dns_policy" => expected_version,
                "reason"     => expected_version,
              )
            )
          end

          if i == 0
            match_created(persister, :container_groups => ContainerGroup.all)
          else
            match_created(persister)
          end
          match_updated(persister)
          match_deleted(persister)
        end

        2.times do |i|
          persister = TestCollector.refresh(
            TestCollector.generate_batches_of_full_container_group_data(
              :settings => settings,
              :ems_name => @ems.name,
              :version  => newest_version(settings),
            )
          )

          ContainerGroup.find_each do |container_group|
            expected_version = expected_version(settings, container_group, newest_version(settings))

            expect(container_group).to(
              have_attributes(
                :name                      => "container_group_#{expected_version}",
                version_col(settings)      => expected_version,
                versions_max_col(settings) => nil,
                versions_col(settings)     => {},
                :reason                    => expected_version.to_s,
                :phase                     => "#{expected_version} status",
              )
            )
          end

          if i == 0
            match_updated(persister, :container_groups => ContainerGroup.all)
          else
            match_updated(persister)
          end
          match_created(persister)
          match_deleted(persister)
        end
      end

      it "check partial then full with the same version and same resource version" do
        2.times do |i|
          persister = TestCollector.refresh(
            TestCollector.generate_batches_of_partial_container_group_data(
              :settings         => settings,
              :ems_name         => @ems.name,
              :version          => newest_version(settings),
              :resource_version => "same_version",
            )
          )

          ContainerGroup.find_each do |container_group|
            expected_version = expected_version(settings, container_group, newest_version(settings))

            expect(container_group).to(
              have_attributes(
                :name                      => nil,
                version_col(settings)      => nil,
                versions_max_col(settings) => expected_version,
                :reason                    => expected_version.to_s,
                :phase                     => "#{expected_version} status",
                :resource_version          => nil
              )
            )

            expect(container_group.send(versions_col(settings))).to(
              match(
                "phase"      => expected_version,
                "dns_policy" => expected_version,
                "reason"     => expected_version,
              )
            )
          end

          if i == 0
            match_created(persister, :container_groups => ContainerGroup.all)
          else
            match_created(persister)
          end
          match_updated(persister)
          match_deleted(persister)
        end

        2.times do |i|
          persister = TestCollector.refresh(
            TestCollector.generate_batches_of_full_container_group_data(
              :settings         => settings,
              :ems_name         => @ems.name,
              :version          => newest_version(settings),
              :resource_version => "same_version",
            )
          )

          ContainerGroup.find_each do |container_group|
            expected_version = expected_version(settings, container_group, newest_version(settings))

            expect(container_group).to(
              have_attributes(
                :name                      => "container_group_#{expected_version}",
                version_col(settings)      => expected_version,
                versions_max_col(settings) => nil,
                versions_col(settings)     => {},
                :reason                    => expected_version.to_s,
                :phase                     => "#{expected_version} status",
                :resource_version          => "same_version",
              )
            )
          end

          if i == 0
            match_updated(persister, :container_groups => ContainerGroup.all)
          else
            match_updated(persister)
          end
          match_created(persister)
          match_deleted(persister)
        end
      end

      it "check full then partial with the bigger version" do
        container_group_created_on = nil

        bigger_newest_version = incremented_newest_version(settings, 1)

        2.times do |i|
          persister = TestCollector.refresh(
            TestCollector.generate_batches_of_full_container_group_data(
              :settings => settings,
              :ems_name => @ems.name,
              :version  => newest_version(settings),
            )
          )

          # Expect the second+ run with same version for each record doesn't change rails versions (the row should
          # not be updated)
          container_group_created_on = ContainerGroup.where(:dns_policy => "1").first.created_on

          if i == 0
            match_created(persister, :container_groups => ContainerGroup.all)
          else
            match_created(persister)
          end
          match_updated(persister)
          match_deleted(persister)
        end

        2.times do |i|
          persister = TestCollector.refresh(
            TestCollector.generate_batches_of_partial_container_group_data(
              :settings => settings,
              :ems_name => @ems.name,
              :version  => bigger_newest_version,
            )
          )

          ContainerGroup.find_each do |container_group|
            expected_version        = expected_version(settings, container_group, newest_version(settings))
            expected_bigger_version = expected_version(settings, container_group, bigger_newest_version)
            expect(container_group).to(
              have_attributes(
                :name                      => "container_group_#{expected_version}",
                version_col(settings)      => expected_version,
                versions_max_col(settings) => expected_bigger_version,
                :reason                    => expected_bigger_version.to_s,
                :phase                     => "#{expected_bigger_version} status",
              )
            )

            expect(container_group.send(versions_col(settings))).to(
              match(
                "phase"      => expected_bigger_version,
                "dns_policy" => expected_bigger_version,
                "reason"     => expected_bigger_version,
              )
            )
          end

          # Expect the second+ run with same version for each record doesn't change rails versions (the row should
          # not be updated)
          container_group_current_created_on = ContainerGroup.where(:dns_policy => "1").first.created_on
          expect(container_group_created_on).to eq(container_group_current_created_on)

          if i == 0
            match_updated(persister, :container_groups => ContainerGroup.all)
          else
            match_updated(persister)
          end
          match_created(persister)
          match_deleted(persister)
        end
      end

      it "check partial then full with the bigger version" do
        bigger_newest_version = incremented_newest_version(settings, 1)

        2.times do |i|
          persister = TestCollector.refresh(
            TestCollector.generate_batches_of_partial_container_group_data(
              :settings => settings,
              :ems_name => @ems.name,
              :version  => newest_version(settings),
            )
          )

          if i == 0
            match_created(persister, :container_groups => ContainerGroup.all)
          else
            match_created(persister)
          end
          match_updated(persister)
          match_deleted(persister)
        end

        2.times do |i|
          persister = TestCollector.refresh(
            TestCollector.generate_batches_of_full_container_group_data(
              :settings => settings,
              :ems_name => @ems.name,
              :version  => bigger_newest_version,
            )
          )

          ContainerGroup.find_each do |container_group|
            expected_bigger_version = expected_version(settings, container_group, bigger_newest_version)

            expect(container_group).to(
              have_attributes(
                :name                      => "container_group_#{expected_bigger_version}",
                version_col(settings)      => expected_bigger_version,
                versions_max_col(settings) => nil,
                versions_col(settings)     => {},
                :reason                    => expected_bigger_version.to_s,
                :phase                     => "#{expected_bigger_version} status",
              )
            )
          end

          if i == 0
            match_updated(persister, :container_groups => ContainerGroup.all)
          else
            match_updated(persister)
          end
          match_created(persister)
          match_deleted(persister)
        end
      end

      it "checks that full refresh with lower version running after partial, will turn to partial updates" do
        bigger_newest_version      = incremented_newest_version(settings, 1)
        even_bigger_newest_version = incremented_newest_version(settings, 2)

        2.times do |i|
          persister = TestCollector.refresh(
            TestCollector.generate_batches_of_partial_container_group_data(
              :settings => settings,
              :ems_name => @ems.name,
              :version  => bigger_newest_version,
            )
          )

          if i == 0
            match_created(persister, :container_groups => ContainerGroup.all)
          else
            match_created(persister)
          end
          match_updated(persister)
          match_deleted(persister)
        end

        2.times do |i|
          persister = TestCollector.generate_batches_of_full_container_group_data(
            :settings    => settings,
            :ems_name    => @ems.name,
            :version     => newest_version(settings),
            :index_start => 0,
            :batch_size  => 2
          )

          TestCollector.generate_batches_of_full_container_group_data(
            :settings    => settings,
            :ems_name    => @ems.name,
            :version     => even_bigger_newest_version,
            :persister   => persister,
            :index_start => 1,
            :batch_size  => 2
          )

          persister = TestCollector.refresh(persister)

          ContainerGroup.find_each do |container_group|
            expected_version             = expected_version(settings, container_group, newest_version(settings))
            expected_bigger_version      = expected_version(settings, container_group, bigger_newest_version)
            expected_even_bigger_version = expected_version(settings, container_group, even_bigger_newest_version)

            if index(container_group) >= 2
              # This gets full row update
              expect(container_group).to(
                have_attributes(
                  :name                      => "container_group_#{expected_even_bigger_version}",
                  :message                   => expected_even_bigger_version.to_s,
                  version_col(settings)      => expected_even_bigger_version,
                  versions_max_col(settings) => nil,
                  versions_col(settings)     => {},
                  :reason                    => expected_even_bigger_version.to_s,
                  :phase                     => "#{expected_even_bigger_version} status",
                )
              )
            else
              # This gets full row, transformed to skeletal update, leading to only updating :name
              expect(container_group).to(
                have_attributes(
                  :name                      => "container_group_#{expected_version}",
                  :message                   => expected_version.to_s,
                  version_col(settings)      => nil,
                  versions_max_col(settings) => expected_bigger_version,
                  :reason                    => expected_bigger_version.to_s,
                  :phase                     => "#{expected_bigger_version} status",
                )
              )

              expect(container_group.send(versions_col(settings))).to(
                match(
                  "dns_policy" => expected_bigger_version,
                  "message"    => expected_version,
                  "name"       => expected_version,
                  "phase"      => expected_bigger_version,
                  "reason"     => expected_bigger_version,
                )
              )
            end
          end

          if i == 0
            match_updated(persister, :container_groups => ContainerGroup.all)
          else
            match_updated(persister)
          end
          match_created(persister)
          match_deleted(persister)
        end
      end

      it "checks that 2 different partial records are batched and saved correctly when starting with older" do
        bigger_newest_version = incremented_newest_version(settings, 1)

        2.times do |i|
          persister = TestCollector.generate_batches_of_partial_container_group_data(
            :settings => settings,
            :ems_name => @ems.name,
            :version  => newest_version(settings),
          )

          TestCollector.generate_batches_of_different_partial_container_group_data(
            :settings    => settings,
            :ems_name    => @ems.name,
            :version     => bigger_newest_version,
            :persister   => persister,
            :index_start => 1,
            :batch_size  => 2
          )

          persister = TestCollector.refresh(persister)

          if i == 0
            match_created(persister, :container_groups => ContainerGroup.all)
          else
            match_created(persister)
          end
          match_updated(persister)
          match_deleted(persister)

          persister = TestCollector.refresh(
            TestCollector.generate_batches_of_different_partial_container_group_data(
              :settings    => settings,
              :ems_name    => @ems.name,
              :version     => bigger_newest_version,
              :index_start => 0,
              :batch_size  => 2
            )
          )

          ContainerGroup.find_each do |container_group|
            expected_version        = expected_version(settings, container_group, newest_version(settings))
            expected_bigger_version = expected_version(settings, container_group, bigger_newest_version)
            expect(container_group).to(
              have_attributes(
                :name                      => nil,
                version_col(settings)      => nil,
                :message                   => expected_bigger_version.to_s,
                versions_max_col(settings) => expected_bigger_version,
                :reason                    => expected_bigger_version.to_s,
                :phase                     => "#{expected_version} status",
              )
            )

            expect(container_group.send(versions_col(settings))).to(
              match(
                "dns_policy" => expected_bigger_version,
                "message"    => expected_bigger_version,
                "phase"      => expected_version,
                "reason"     => expected_bigger_version,
              )
            )
          end

          if i == 0
            match_updated(persister, :container_groups => ContainerGroup.where(:dns_policy => %w(0 1)))
          else
            match_updated(persister)
          end
          match_created(persister)
          match_deleted(persister)
        end
      end

      it "checks that 2 different partial records are batched and saved correctly when starting with newer" do
        bigger_newest_version = incremented_newest_version(settings, 1)

        persister = TestCollector.generate_batches_of_partial_container_group_data(
          :settings => settings,
          :ems_name => @ems.name,
          :version  => bigger_newest_version,
        )

        TestCollector.generate_batches_of_different_partial_container_group_data(
          :settings    => settings,
          :ems_name    => @ems.name,
          :version     => newest_version(settings),
          :persister   => persister,
          :index_start => 1,
          :batch_size  => 2
        )

        persister = TestCollector.refresh(persister)

        ContainerGroup.find_each do |container_group|
          expected_version        = expected_version(settings, container_group, newest_version(settings))
          expected_bigger_version = expected_version(settings, container_group, bigger_newest_version)
          expect(container_group).to(
            have_attributes(
              :name                      => nil,
              version_col(settings)      => nil,
              versions_max_col(settings) => expected_bigger_version,
              :reason                    => expected_bigger_version.to_s,
              :phase                     => "#{expected_bigger_version} status",
            )
          )

          if index(container_group) >= 2
            # version is only set for container_groups >= 2
            expect(container_group).to(
              have_attributes(
                :message => expected_version.to_s,
              )
            )
            expect(container_group.send(versions_col(settings))).to(
              match(
                "dns_policy" => expected_bigger_version,
                "message"    => expected_version,
                "phase"      => expected_bigger_version,
                "reason"     => expected_bigger_version,
              )
            )
          else
            expect(container_group).to(
              have_attributes(
                :message => nil,
              )
            )
            expect(container_group.send(versions_col(settings))).to(
              match(
                "dns_policy" => expected_bigger_version,
                "phase"      => expected_bigger_version,
                "reason"     => expected_bigger_version,
              )
            )
          end
        end

        match_created(persister, :container_groups => ContainerGroup.all)
        match_updated(persister)
        match_deleted(persister)

        persister = TestCollector.refresh(
          TestCollector.generate_batches_of_different_partial_container_group_data(
            :settings    => settings,
            :ems_name    => @ems.name,
            :version     => newest_version(settings),
            :index_start => 0,
            :batch_size  => 2
          )
        )

        ContainerGroup.find_each do |container_group|
          expected_version        = expected_version(settings, container_group, newest_version(settings))
          expected_bigger_version = expected_version(settings, container_group, bigger_newest_version)
          expect(container_group).to(
            have_attributes(
              :name                      => nil,
              version_col(settings)      => nil,
              versions_max_col(settings) => expected_bigger_version,
              :reason                    => expected_bigger_version.to_s,
              :phase                     => "#{expected_bigger_version} status",
              :message                   => expected_version.to_s,
            )
          )

          expect(container_group.send(versions_col(settings))).to(
            match(
              "dns_policy" => expected_bigger_version,
              "message"    => expected_version,
              "phase"      => expected_bigger_version,
              "reason"     => expected_bigger_version,
            )
          )
        end

        match_created(persister)
        match_updated(persister, :container_groups => ContainerGroup.where(:dns_policy => %w(0 1)))
        match_deleted(persister)
      end

      it "checks that 2 different full rows are saved correctly when starting with newer" do
        bigger_newest_version = incremented_newest_version(settings, 1)

        2.times do |i|
          persister = TestCollector.generate_batches_of_full_container_group_data(
            :settings => settings,
            :ems_name => @ems.name,
            :version  => bigger_newest_version,
          )

          TestCollector.generate_batches_of_full_container_group_data(
            :settings    => settings,
            :ems_name    => @ems.name,
            :version     => newest_version(settings),
            :persister   => persister,
            :index_start => 1,
            :batch_size  => 2
          )

          persister = TestCollector.refresh(persister)

          ContainerGroup.find_each do |container_group|
            expected_bigger_version = expected_version(settings, container_group, bigger_newest_version)
            expect(container_group).to(
              have_attributes(
                :name                      => "container_group_#{expected_bigger_version}",
                version_col(settings)      => expected_bigger_version,
                versions_col(settings)     => {},
                versions_max_col(settings) => nil,
                :message                   => expected_bigger_version.to_s,
                :reason                    => expected_bigger_version.to_s,
                :phase                     => "#{expected_bigger_version} status",
              )
            )
          end

          if i == 0
            match_created(persister, :container_groups => ContainerGroup.all)
          else
            match_created(persister)
          end
          match_updated(persister)
          match_deleted(persister)

          persister = TestCollector.refresh(
            TestCollector.generate_batches_of_full_container_group_data(
              :settings    => settings,
              :ems_name    => @ems.name,
              :version     => newest_version(settings),
              :index_start => 0,
              :batch_size  => 2
            )
          )

          ContainerGroup.find_each do |container_group|
            expected_bigger_version = expected_version(settings, container_group, bigger_newest_version)
            expect(container_group).to(
              have_attributes(
                :name                      => "container_group_#{expected_bigger_version}",
                version_col(settings)      => expected_bigger_version,
                versions_col(settings)     => {},
                versions_max_col(settings) => nil,
                :message                   => expected_bigger_version.to_s,
                :reason                    => expected_bigger_version.to_s,
                :phase                     => "#{expected_bigger_version} status",
              )
            )
          end

          match_created(persister)
          match_updated(persister)
          match_deleted(persister)
        end
      end
    end
  end

  private

  def index(container_group)
    container_group.dns_policy.to_i
  end

  def resource_counter_expected_version(container_group, newest_version)
    newest_version + index(container_group) * 100
  end

  def resource_counter_newest_version
    42
  end

  def resource_timestamp_expected_version(vm, newest_timestamp)
    newest_timestamp + index(vm).minutes
  end

  def resource_timestamp_newest_version
    time_parse("2018-08-07 08:12:17 UTC")
  end

  # def version_parse(version)
  #   version.to_i
  # end

  def time_parse(time)
    Time.find_zone("UTC").parse(time)
  end

  def version_col(settings)
    settings[:parallel_saving_column].to_sym
  end

  def versions_col(settings)
    "#{settings[:parallel_saving_column]}s".to_sym
  end

  def versions_max_col(settings)
    "#{settings[:parallel_saving_column]}s_max".to_sym
  end

  def newest_version(settings)
    send("#{settings[:parallel_saving_column]}_newest_version")
  end

  def expected_version(settings, entity, newest_version)
    send("#{settings[:parallel_saving_column]}_expected_version", entity, newest_version)
  end

  def incremented_newest_version(settings, increment)
    inc = if settings[:parallel_saving_column] == "resource_timestamp"
            increment.seconds
          else
            increment
          end

    newest_version(settings) + inc
  end
end
