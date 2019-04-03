require_relative 'archived_mixin'

class Flavor < ActiveRecord::Base
  include ArchivedMixin

  belongs_to :ext_management_system, :foreign_key => :ems_id
end
