class Hardware < ActiveRecord::Base
  belongs_to :vm_or_template, :class_name => "VmOrTemplate"
  has_many :disks, -> { order(:location) }, :dependent => :destroy
  has_many :networks, :dependent => :destroy
end
