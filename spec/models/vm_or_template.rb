require_relative 'archived_mixin'

class VmOrTemplate < ActiveRecord::Base
  include ArchivedMixin

  self.table_name = "vms"

  belongs_to :ext_management_system, :foreign_key => :ems_id
  belongs_to :flavor
  belongs_to :source_region
  belongs_to :subscription

  has_one :hardware, :dependent => :destroy
  has_many :disks, :through => :hardware

  validates_presence_of :name, :location

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
