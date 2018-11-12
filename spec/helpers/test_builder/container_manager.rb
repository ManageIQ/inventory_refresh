require_relative "../test_builder"
class TestBuilder::ContainerManager < ::TestBuilder
  # TODO: (agrare) Targeted refreshes will require adjusting the associations / arels. (duh)
  def container_projects
    add_properties(
      :secondary_refs => {:by_name => %i(name)},
      :delete_method  => :disconnect_inv,
      :model_class    => ContainerProject,
    )
    add_common_default_values
  end

  def container_nodes
    add_properties(
      :model_class    => ::ContainerNode,
      :secondary_refs => {:by_name => %i(name)},
      :delete_method  => :disconnect_inv
    )
    add_common_default_values
  end

  # images have custom_attributes but that's done conditionally in openshift parser
  def container_images
    add_properties(
      # TODO: (bpaskinc) old save matches on [:image_ref, :container_image_registry_id]
      # TODO: (bpaskinc) should match on digest when available
      # TODO: (mslemr) provider-specific class exists (openshift), but specs fail with them (?)
      :model_class            => ::ContainerImage,
      :manager_ref            => %i(image_ref),
      :delete_method          => :disconnect_inv,
      :custom_reconnect_block => custom_reconnect_block
    )
    add_common_default_values
  end

  def container_image_registries
    add_properties(
      :manager_ref => %i(host port),
      :model_class => ContainerImageRegistry,
    )
    add_common_default_values
  end

  def container_groups
    add_properties(
      :model_class            => ContainerGroup,
      :secondary_refs         => {:by_container_project_and_name => %i(container_project name)},
      :attributes_blacklist   => %i(namespace),
      :delete_method          => :disconnect_inv,
      :custom_reconnect_block => custom_reconnect_block
    )
    add_common_default_values
  end

  def containers
    add_properties(
      :model_class            => Container,
      # parser sets :ems_ref => "#{pod_id}_#{container.name}_#{container.image}"
      :delete_method          => :disconnect_inv,
      :custom_reconnect_block => custom_reconnect_block
    )
    add_common_default_values
  end

  def nested_containers
    add_properties(
      :model_class => NestedContainer,
      :manager_ref => %i(container_group name),
    )
  end

  def container_replicators
    add_properties(
      :secondary_refs       => {:by_container_project_and_name => %i(container_project name)},
      :attributes_blacklist => %i(namespace),
      :model_class          => ContainerReplicator,
    )
    add_common_default_values
  end

  def container_build_pods
    add_properties(
      # TODO: (bpaskinc) convert namespace column -> container_project_id?
      :manager_ref    => %i(namespace name),
      :secondary_refs => {:by_namespace_and_name => %i(namespace name)},
      :model_class    => ContainerBuildPod,
    )
    add_common_default_values
  end

  protected

  def custom_reconnect_block
    # TODO(lsmola) once we have DB unique indexes, we can stop using manual reconnect, since it adds processing time
    lambda do |inventory_collection, inventory_objects_index, attributes_index|
      relation = inventory_collection.model_class.where(:ems_id => inventory_collection.parent.id).archived

      # Skip reconnect if there are no archived entities
      return if relation.archived.count <= 0
      raise "Allowed only manager_ref size of 1, got #{inventory_collection.manager_ref}" if inventory_collection.manager_ref.count > 1

      inventory_objects_index.each_slice(1000) do |batch|
        relation.where(inventory_collection.manager_ref.first => batch.map(&:first)).each do |record|
          index = inventory_collection.object_index_with_keys(inventory_collection.manager_ref_to_cols, record)

          # We need to delete the record from the inventory_objects_index and attributes_index, otherwise it
          # would be sent for create.
          inventory_object = inventory_objects_index.delete(index)
          hash             = attributes_index.delete(index)

          # Make the entity active again, otherwise we would be duplicating nested entities
          hash[:archived_on] = nil

          record.assign_attributes(hash.except(:id, :type))
          if !inventory_collection.check_changed? || record.changed?
            record.save!
            inventory_collection.store_updated_records(record)
          end

          inventory_object.id = record.id
        end
      end
    end
  end
end
