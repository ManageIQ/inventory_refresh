class Hardware < ActiveRecord::Base
  belongs_to :vm_or_template, :class_name => "VmOrTemplate"
  has_many :disks, -> { order(:location) }
  has_many :networks
end
