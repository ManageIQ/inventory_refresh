require_relative 'archived_mixin'

class Hardware < ActiveRecord::Base
  include ArchivedMixin

  belongs_to :vm_or_template, :class_name => "VmOrTemplate"
  has_many :disks, -> { order(:location) }, :dependent => :destroy
  has_many :networks, :dependent => :destroy
end
