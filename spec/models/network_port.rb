class NetworkPort < ActiveRecord::Base
  belongs_to :ext_management_system, :foreign_key => :ems_id
  belongs_to :device, :polymorphic => true
end
