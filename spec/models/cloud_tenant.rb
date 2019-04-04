require_relative 'archived_mixin'

class CloudTenant < ActiveRecord::Base
  include ArchivedMixin

  belongs_to :ext_management_system, :foreign_key => :ems_id
  has_many :vms
end
