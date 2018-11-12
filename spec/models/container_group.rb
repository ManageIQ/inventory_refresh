require_relative 'archived_mixin'

class ContainerGroup < ActiveRecord::Base
  include ArchivedMixin

  has_many :containers, :dependent => :destroy
  has_many :nested_containers, :dependent => :destroy
  has_many :container_images, -> { distinct }, :through => :containers
  belongs_to :ext_management_system, :foreign_key => "ems_id"
  belongs_to :container_node
  belongs_to :container_replicator
  belongs_to :container_project
  belongs_to :container_build_pod
end
