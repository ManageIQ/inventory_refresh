require_relative 'archived_mixin'

class ContainerImage < ActiveRecord::Base
  include ArchivedMixin

  belongs_to :container_image_registry
  belongs_to :ext_management_system, :foreign_key => "ems_id"
  has_many :containers
  has_many :container_nodes, -> { distinct }, :through => :containers
  has_many :container_groups, -> { distinct }, :through => :containers
  has_many :container_projects, -> { distinct }, :through => :container_groups

  def disconnect_inv
    return if archived?

    _log.info("Disconnecting Image [#{name}] id [#{id}] from EMS [#{ext_management_system.name}] id [#{ext_management_system.id}]")
    self.container_image_registry = nil
    self.archived_at = Time.now.utc
    save
  end

  def self.disconnect_inv(ids)
    _log.info "Disconnecting Images [#{ids}]"
    where(:id => ids).update_all(:container_image_registry_id => nil, :archived_at => Time.now.utc)
  end
end
