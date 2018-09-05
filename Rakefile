require "bundler/gem_tasks"
require "rspec/core/rake_task"

namespace :spec do
  task :db_drop do
    connection("template1").execute("DROP DATABASE IF EXISTS #{test_database_name}")
  end

  task :db_create do
    connection("template1").execute("CREATE DATABASE #{test_database_name}")
  end

  task :db_load_schema do
    require "active_record"
    ActiveRecord::Schema.verbose = false
    load File.join(__dir__, %w{spec schema.rb})
  end

  desc "Setup test database"
  task :setup => [:db_drop, :db_create, :db_load_schema]

  def pg_opts
    {
      :adapter      => "postgresql",
      :encoding     => "utf8",
      :username     => "root",
      :pool         => 5,
      :wait_timeout => 5,
      :min_messages => "warning",
    }
  end

  def test_database_name
    "inventory_refresh_dummy_test"
  end

  def connection(database_name)
    require "active_record"
    ActiveRecord::Base.establish_connection pg_opts.merge(:database => database_name)
    ActiveRecord::Base.connection
  end
end

RSpec::Core::RakeTask.new(:spec)

task :default => :spec
