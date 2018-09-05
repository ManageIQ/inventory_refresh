require 'active_record'

RSpec.configure do |config|
  config.around do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end

def load_schema
  ActiveRecord::Schema.verbose = false
end
