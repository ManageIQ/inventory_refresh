require_relative 'archived_mixin'

class VmOrTemplate < ActiveRecord::Base
  include ArchivedMixin

  self.table_name = "vms"

  belongs_to :ext_management_system, :foreign_key => :ems_id
  belongs_to :flavor

  has_one :hardware, :dependent => :destroy
  has_many :disks, :through => :hardware

  validates_presence_of :name, :location
end
