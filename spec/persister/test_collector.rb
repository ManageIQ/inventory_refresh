require_relative '../helpers/test_persister/containers'

class TestCollector
  class << self
    def generate_batches_of_partial_container_group_data(ems_name:, version:, settings:, batch_size: 4, index_start: 0,
                                                         persister: nil, resource_version: nil)
      ems = ExtManagementSystem.find_by(:name => ems_name)
      persister ||= new_persister(ems, settings)

      (index_start * batch_size..((index_start + 1) * batch_size - 1)).each do |index|
        parse_partial_container_group(index, persister, settings, incremented_counter(settings, version, index),
                                      resource_version)
      end

      persister
    end

    def generate_batches_of_different_partial_container_group_data(ems_name:, version:, settings:, batch_size: 4,
                                                                   index_start: 0, persister: nil, resource_version: nil)
      ems = ExtManagementSystem.find_by(:name => ems_name)
      persister ||= new_persister(ems, settings)

      (index_start * batch_size..((index_start + 1) * batch_size - 1)).each do |index|
        parse_another_partial_container_group(index, persister, settings, incremented_counter(settings, version, index),
                                              resource_version)
      end

      persister
    end

    def generate_batches_of_full_container_group_data(ems_name:, version:, settings:, batch_size: 4, index_start: 0,
                                                      persister: nil, resource_version: nil)
      ems = ExtManagementSystem.find_by(:name => ems_name)
      persister ||= new_persister(ems, settings)

      (index_start * batch_size..((index_start + 1) * batch_size - 1)).each do |index|
        parse_container_group(index, persister, settings, incremented_counter(settings, version, index), resource_version)
      end

      persister
    end

    def parse_another_partial_container_group(index, persister, settings, partial_newest, resource_version)
      data                    = {
        :ems_ref              => "container_group_#{index}",
        version_col(settings) => partial_newest,
        :reason               => partial_newest,
        :message              => partial_newest,
        :dns_policy           => index.to_s,
      }
      data[:resource_version] = resource_version if resource_version

      persister.container_groups.build_partial(data)
    end

    def parse_partial_container_group(index, persister, settings, partial_newest, resource_version)
      data                    = {
        :ems_ref              => "container_group_#{index}",
        :phase                => "#{partial_newest} status",
        version_col(settings) => partial_newest,
        :reason               => partial_newest,
        :dns_policy           => index.to_s,
      }
      data[:resource_version] = resource_version if resource_version

      persister.container_groups.build_partial(data)
    end

    def parse_container_group(index, persister, settings, counter, resource_version)
      data                    = {
        :ems_ref              => "container_group_#{index}",
        :dns_policy           => index.to_s,
        :name                 => "container_group_#{counter}",
        :phase                => "#{counter} status",
        version_col(settings) => counter,
        :reason               => counter,
        :message              => counter,
      }
      data[:resource_version] = resource_version if resource_version

      persister.container_groups.build(data)
    end

    def refresh(persister)
      manager = persister.manager
      use_ar_object = persister.inventory_collections.first.use_ar_object

      persister = persister.class.from_json(persister.to_json, manager)
      # :use_ar_object is not exposed to be serializable, it's taken from Persister class, so it's not changeable
      # in the runtime.
      persister.inventory_collections.each { |x| x.instance_variable_set(:@use_ar_object, use_ar_object) }

      persister.persist!
      persister
    end

    def new_persister(ems, settings)
      TestPersister::Containers.new(ems, :use_ar_object => settings[:use_ar_object])
    end

    def version_col(settings)
      settings[:parallel_saving_column].to_sym
    end

    def incremented_counter(settings, counter, increment)
      inc = if settings[:parallel_saving_column] == "resource_timestamp"
              increment.minutes
            else
              increment * 100
            end

      counter + inc
    end
  end
end
