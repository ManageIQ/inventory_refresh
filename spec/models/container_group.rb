require_relative 'archived_mixin'

class ContainerGroup < ActiveRecord::Base
  include ArchivedMixin

  has_many :containers, :dependent => :destroy
  has_many :container_images, -> { distinct }, :through => :containers
  belongs_to :ext_management_system, :foreign_key => "ems_id"
  belongs_to :container_node
  belongs_to :container_replicator
  belongs_to :container_project
  belongs_to :container_build_pod

  def disconnect_inv
    return if archived?
    _log.info("Disconnecting Pod [#{name}] id [#{id}] from EMS [#{ext_management_system.name}] id [#{ext_management_system.id}]")
    self.containers.each(&:disconnect_inv)
    self.container_services = []
    self.container_replicator_id = nil
    self.container_build_pod_id = nil
    # Keeping old_container_project_id for backwards compatibility, we will need a migration that is putting it back to
    # container_project_id
    self.old_container_project_id = self.container_project_id
    self.deleted_on = Time.now.utc
    save
  end
end
