class TestBuilder
  module Shared
    extend ActiveSupport::Concern

    included do
      INVENTORY_RECONNECT_BLOCK = lambda do |inventory_collection, inventory_objects_index, attributes_index|
        relation = inventory_collection.model_class.where(:ems_id => nil)

        return if relation.count <= 0

        inventory_objects_index.each_slice(100) do |batch|
          batch_refs = batch.map(&:first)
          relation.where(inventory_collection.manager_ref.first => batch_refs).order(:id => :asc).each do |record|
            index = inventory_collection.object_index_with_keys(inventory_collection.manager_ref_to_cols, record)

            # We need to delete the record from the inventory_objects_index
            # and attributes_index, otherwise it would be sent for create.
            inventory_object = inventory_objects_index.delete(index)
            hash = attributes_index.delete(index)

            # Skip if hash is blank, which can happen when having several archived entities with the same ref
            next unless hash

            record.assign_attributes(hash.except(:id, :type))
            if !inventory_collection.check_changed? || record.changed?
              record.save!
              inventory_collection.store_updated_records(record)
            end

            inventory_object.id = record.id
          end
        end
      end.freeze

      def vms
        vm_template_shared
      end

      def miq_templates
        vm_template_shared
        add_default_values(
          :template => true
        )
      end

      def vm_template_shared
        add_properties(
          :delete_method          => :disconnect_inv,
          :attributes_blacklist   => %i(genealogy_parent),
          :custom_reconnect_block => INVENTORY_RECONNECT_BLOCK
        )

        add_default_values(
          :ems_id => ->(persister) { persister.manager.id }
        )
      end

      def hardwares
        add_properties(
          :manager_ref                  => %i(vm_or_template),
          :parent_inventory_collections => %i(vms miq_templates),
          :use_ar_object                => true, # TODO(lsmola) just because of default value on cpu_sockets, this can be fixed by separating instances_hardwares and images_hardwares
        )
      end

      def networks
        add_properties(
          :manager_ref                  => %i(hardware description),
          :parent_inventory_collections => %i(vms)
        )
      end

      def disks
        add_properties(
          :manager_ref                  => %i(hardware device_name),
          :parent_inventory_collections => %i(vms)
        )
      end

      def source_regions
        add_common_default_values
      end

      def subscriptions
        add_common_default_values
      end

      protected

      def add_common_default_values
        add_default_values(:ems_id => ->(persister) { persister.manager.id })
      end
    end
  end
end
