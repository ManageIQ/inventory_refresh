class RefreshStatePart < ActiveRecord::Base
  belongs_to :refresh_state
  belongs_to :ext_management_system, :foreign_key => :ems_id
end
