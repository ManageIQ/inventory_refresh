if ENV['CI']
  require 'simplecov'
  SimpleCov.start
end

require "bundler/setup"
require "inventory_refresh"
require "active_record"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }
$LOAD_PATH << File.join(__dir__, "models")
Dir[File.expand_path("models/**/*.rb", __dir__)].each { |f| require f }

ActiveRecord::Base.establish_connection(
  :adapter      => "postgresql",
  :encoding     => "utf8",
  :username     => "root",
  :pool         => 5,
  :wait_timeout => 5,
  :min_messages => "warning",
  :database     => "inventory_refresh_dummy_test"
)
