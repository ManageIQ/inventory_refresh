class ExtManagementSystem < ::ActiveRecord::Base
  has_many :hardwares,         :through     => :vms_and_templates
  has_many :hosts,             :foreign_key => :ems_id, :dependent => :destroy
  has_many :physical_servers,  :foreign_key => :ems_id, :dependent => :destroy
  has_many :vms,               :foreign_key => :ems_id, :dependent => :destroy
  has_many :miq_templates,     :foreign_key => :ems_id, :dependent => :destroy
  has_many :vms_and_templates, :foreign_key => :ems_id, :class_name => "VmOrTemplate"
  has_many :hardwares,         :through => :vms_and_templates
  has_many :disks,             :through => :hardwares
  has_many :networks,          :through => :hardwares
end
