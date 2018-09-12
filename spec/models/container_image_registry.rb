require_relative 'archived_mixin'

class ContainerImageRegistry < ActiveRecord::Base
  include ArchivedMixin

  belongs_to :ext_management_system, :foreign_key => "ems_id"
  has_many :container_images, :dependent => :nullify
  has_many :containers, :through => :container_images
end
