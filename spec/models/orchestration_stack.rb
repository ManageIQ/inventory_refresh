require "ancestry"

class OrchestrationStack < ActiveRecord::Base
  has_ancestry

  belongs_to :ext_management_system, :foreign_key => :ems_id
  has_many   :resources,  :dependent => :destroy, :foreign_key => :stack_id, :class_name => "OrchestrationStackResource"
  alias_method :orchestration_stack_resources,  :resources
end
