require_relative 'test_containers_persister'

class TestCollector
  class << self
    def generate_batches_of_partial_container_group_data(ems_name:, version:, settings:, batch_size: 4, index_start: 0, persister: nil)
      ems = ExtManagementSystem.find_by(:name => ems_name)
      persister ||= new_persister(ems)

      (index_start * batch_size..((index_start + 1) * batch_size - 1)).each do |index|
        parse_partial_container_group(index, persister, settings, incremented_counter(settings, version, index))
      end

      persister
    end

    def generate_batches_of_different_partial_container_group_data(ems_name:, version:, settings:, batch_size: 4, index_start: 0, persister: nil)
      ems = ExtManagementSystem.find_by(:name => ems_name)
      persister ||= new_persister(ems)

      (index_start * batch_size..((index_start + 1) * batch_size - 1)).each do |index|
        parse_another_partial_container_group(index, persister, settings, incremented_counter(settings, version, index))
      end

      persister
    end

    def generate_batches_of_full_container_group_data(ems_name:, version:, settings:, batch_size: 4, index_start: 0, persister: nil)
      ems = ExtManagementSystem.find_by(:name => ems_name)
      persister ||= new_persister(ems)

      (index_start * batch_size..((index_start + 1) * batch_size - 1)).each do |index|
        parse_container_group(index, persister, settings, incremented_counter(settings, version, index))
      end

      persister
    end

    def parse_another_partial_container_group(index, persister, settings, partial_newest)
      persister.container_groups.build_partial(
        :ems_ref              => "container_group_#{index}",
        version_col(settings) => partial_newest,
        :reason               => partial_newest,
        :message              => partial_newest,
        :dns_policy           => index.to_s,
      )
    end

    def parse_partial_container_group(index, persister, settings, partial_newest)
      persister.container_groups.build_partial(
        :ems_ref              => "container_group_#{index}",
        :phase                => "#{partial_newest} status",
        version_col(settings) => partial_newest,
        :reason               => partial_newest,
        :dns_policy           => index.to_s,
      )
    end

    def parse_container_group(index, persister, settings, counter)
      persister.container_groups.build(
        :ems_ref              => "container_group_#{index}",
        :dns_policy           => index.to_s,
        :name                 => "container_group_#{counter}",
        :phase                => "#{counter} status",
        version_col(settings) => counter,
        :reason               => counter,
        :message              => counter,
      )
    end

    def refresh(persister)
      persister = persister.class.from_json(persister.to_json)
      persister.persist!
      persister
    end

    def new_persister(ems)
      TestContainersPersister.new(ems, ems)
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
