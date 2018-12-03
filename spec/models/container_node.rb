require_relative 'archived_mixin'

class ContainerNode < ActiveRecord::Base
  include ArchivedMixin

  belongs_to :ext_management_system, :foreign_key => "ems_id"
  has_many   :container_groups, -> { active }
  has_many   :containers, :through => :container_groups
  has_many   :container_images, -> { distinct }, :through => :container_groups
  has_many   :container_replicators, -> { distinct }, :through => :container_groups

  def disconnect_inv
    return if archived?
    _log.info("Disconnecting Node [#{name}] id [#{id}] from EMS [#{ext_management_system.name}]" \
    "id [#{ext_management_system.id}] ")
    self.archived_at = Time.now.utc
    save
  end
end
