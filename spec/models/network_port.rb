require_relative 'archived_mixin'

class NetworkPort < ActiveRecord::Base
  include ArchivedMixin

  belongs_to :ext_management_system, :foreign_key => :ems_id
  belongs_to :device, :polymorphic => true
end
