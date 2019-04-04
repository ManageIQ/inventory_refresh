class OrchestrationStack < ActiveRecord::Base
  belongs_to :ext_management_system, :foreign_key => :ems_id
  belongs_to :parent, :class_name => "OrchestrationStack"

  has_many   :resources,  :dependent => :destroy, :foreign_key => :stack_id, :class_name => "OrchestrationStackResource"
  alias_method :orchestration_stack_resources,  :resources
end
