class RefreshState < ActiveRecord::Base
  belongs_to :ext_management_system, :foreign_key => :ems_id
  has_many :refresh_state_parts

  def self.owner_ref(owner)
    {
      :ems_id => owner.id,
    }
  end
end
