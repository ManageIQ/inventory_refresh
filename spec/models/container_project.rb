require_relative 'archived_mixin'

class ContainerProject < ActiveRecord::Base
  include ArchivedMixin

  belongs_to :ext_management_system, :foreign_key => "ems_id"
  has_many :container_groups, -> { active }
  has_many :container_replicators
  has_many :containers, :through => :container_groups
  has_many :container_images, -> { distinct }, :through => :container_groups
  has_many :container_nodes, -> { distinct }, :through => :container_groups

  def disconnect_inv
    return if archived?
    _log.info("Disconnecting Container Project [#{name}] id [#{id}] from EMS [#{ext_management_system.name}] id [#{ext_management_system.id}]")
    self.deleted_on = Time.now.utc
    save
  end
end
