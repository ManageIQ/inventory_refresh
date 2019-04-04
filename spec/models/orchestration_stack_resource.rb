require_relative 'archived_mixin'

class OrchestrationStackResource < ActiveRecord::Base
  include ArchivedMixin

  belongs_to :stack, :class_name => "OrchestrationStack"
end
