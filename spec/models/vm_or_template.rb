class VmOrTemplate < ActiveRecord::Base
  self.table_name = "vms"

  belongs_to :ext_management_system, :foreign_key => :ems_id
  belongs_to :flavor

  has_one :hardware
  has_many :disks, :through => :hardware

  def disconnect_inv
    disconnect_ems
  end

  def disconnect_ems(e = nil)
    if e.nil? || ext_management_system == e
      self.ext_management_system = nil
      save
    end
  end
end
