require_relative 'archived_mixin'

class Container < ActiveRecord::Base
  include ArchivedMixin

  belongs_to :container_group
  belongs_to :ext_management_system, :foreign_key => :ems_id
  has_one    :container_node, :through => :container_group
  has_one    :container_replicator, :through => :container_group
  has_one    :container_project, :through => :container_group
  belongs_to :container_image
  has_one    :container_image_registry, :through => :container_image

  def disconnect_inv
    return if archived?

    _log.info("Disconnecting Container [#{name}] id [#{id}] from EMS")
    self.archived_at = Time.now.utc
    save
  end
end
