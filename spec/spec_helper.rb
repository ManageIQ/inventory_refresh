if ENV['CI']
  require 'simplecov'
  SimpleCov.start
end

require "bundler/setup"
require "inventory_refresh"
require "active_record"
require "active_support/all"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

InventoryRefresh.logger = Logger.new($stdout)
InventoryRefresh.logger.level = Logger::ERROR

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |f| require f }
$LOAD_PATH << File.join(__dir__, "models")
Dir[File.expand_path("models/**/*.rb", __dir__)].sort.each { |f| require f }

puts
puts "\e[93mUsing ActiveRecord #{ActiveRecord.version}\e[0m"

require 'yaml'
connection_spec =
  if YAML.respond_to?(:safe_load)
    YAML.safe_load(File.read(File.join(__dir__, %w[.. config database.yml])), :aliases => true)
  else
    YAML.load_file(File.join(__dir__, %w[.. config database.yml]))
  end
ActiveRecord::Base.establish_connection(connection_spec["test"])
