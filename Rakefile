require "bundler/gem_tasks"
require "rspec/core/rake_task"

namespace :spec do
  task :db_drop do
    with_connection("template1") { |conn| conn.execute("DROP DATABASE IF EXISTS #{test_database_name}") }
  end

  task :db_create do
    with_connection("template1") { |conn| conn.execute("CREATE DATABASE #{test_database_name}") }
  end

  task :db_load_schema do
    require "active_record"
    with_connection(test_database_name) { load File.join(__dir__, %w[spec schema.rb]) }
  end

  desc "Setup test database"
  task :setup => [:db_drop, :db_create, :db_load_schema]

  def connection_spec
    require 'yaml'
    @connection_spec ||=
      if YAML.respond_to?(:safe_load)
        YAML.safe_load(File.read(File.join(__dir__, %w[config database.yml])), :aliases => true)
      else
        YAML.load_file(File.join(__dir__, %w[config database.yml]))
      end
  end

  def test_database_name
    connection_spec["test"]["database"]
  end

  def with_connection(database_name)
    require "active_record"
    pool = ActiveRecord::Base.establish_connection(connection_spec["test"].merge("database" => database_name))
    yield ActiveRecord::Base.connection
  ensure
    pool&.disconnect!
  end
end

RSpec::Core::RakeTask.new(:spec)

task :default => :spec
