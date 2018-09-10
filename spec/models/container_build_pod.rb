class ContainerBuildPod < ActiveRecord::Base
  belongs_to :ext_management_system, :foreign_key => "ems_id"

  has_one :container_group
end
