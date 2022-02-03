class AvailabilityZone < ActiveRecord::Base
  belongs_to :ext_management_system, :foreign_key => :ems_id
  has_many   :vms
end
