require_relative 'archived_mixin'

class ContainerReplicator < ActiveRecord::Base
  include ArchivedMixin

  belongs_to :ext_management_system, :foreign_key => "ems_id"
  has_many :container_groups
  belongs_to :container_project
  has_many :container_nodes, -> { distinct }, :through => :container_groups
end
