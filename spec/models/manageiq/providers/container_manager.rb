require "manageiq/providers/base_manager"

module ManageIQ
  module Providers
    class ContainerManager < ManageIQ::Providers::BaseManager
      has_many :container_nodes, -> { active }, :foreign_key => :ems_id
      has_many :container_groups, -> { active }, :foreign_key => :ems_id
      has_many :container_replicators, :foreign_key => :ems_id, :dependent => :destroy
      has_many :containers, -> { active }, :foreign_key => :ems_id
      has_many :container_build_pods, :foreign_key => :ems_id, :dependent => :destroy
      has_many :container_projects, -> { active }, :foreign_key => :ems_id
      has_many :container_image_registries, :foreign_key => :ems_id, :dependent => :destroy
      has_many :container_images, -> { active }, :foreign_key => :ems_id, :dependent => :destroy

      has_many :nested_containers, :through => :container_groups

      # Archived and active entities to destroy when the container manager is deleted
      has_many :all_containers, :foreign_key => :ems_id, :dependent => :destroy, :class_name => "Container"
      has_many :all_container_groups, :foreign_key => :ems_id, :dependent => :destroy, :class_name => "ContainerGroup"
      has_many :all_container_projects, :foreign_key => :ems_id, :dependent => :destroy, :class_name => "ContainerProject"
      has_many :all_container_images, :foreign_key => :ems_id, :dependent => :destroy, :class_name => "ContainerImage"
      has_many :all_container_nodes, :foreign_key => :ems_id, :dependent => :destroy, :class_name => "ContainerNode"
    end
  end
end
