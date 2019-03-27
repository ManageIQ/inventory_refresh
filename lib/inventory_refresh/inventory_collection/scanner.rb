require "active_support/core_ext/module/delegation"

module InventoryRefresh
  class InventoryCollection
    class Scanner
      class << self
        # Scanning inventory_collections for dependencies and references, storing the results in the inventory_collections
        # themselves. Dependencies are needed for building a graph, references are needed for effective DB querying, where
        # we can load all referenced objects of some InventoryCollection by one DB query.
        #
        # @param inventory_collections [Array<InventoryRefresh::InventoryCollection>] Array of InventoryCollection objects
        def scan!(inventory_collections)
          indexed_inventory_collections = inventory_collections.index_by(&:name)

          inventory_collections.each do |inventory_collection|
            new(inventory_collection, indexed_inventory_collections, build_association_hash(inventory_collections)).scan!
          end

          inventory_collections.each do |inventory_collection|
            inventory_collection.dependencies.each do |dependency|
              dependency.dependees << inventory_collection
            end
          end
        end

        def build_association_hash(inventory_collections)
          associations_hash = {}
          parents = inventory_collections.map(&:parent).compact.uniq
          parents.each do |parent|
            parent.class.reflect_on_all_associations(:has_many).each do |association|
              through_assoc = association.options.try(:[], :through)
              associations_hash[association.name] = through_assoc if association.options.try(:[], :through)
            end
          end
          associations_hash
        end
      end

      attr_reader :associations_hash, :inventory_collection, :indexed_inventory_collections

      # Boolean helpers the scanner uses from the :inventory_collection
      delegate :inventory_object_lazy?,
               :inventory_object?,
               :targeted?,
               :to => :inventory_collection

      # Methods the scanner uses from the :inventory_collection
      delegate :data,
               :find_or_build,
               :manager_ref,
               :saver_strategy,
               :to => :inventory_collection

      # The data scanner modifies inside of the :inventory_collection
      delegate :all_manager_uuids_scope,
               :association,
               :arel,
               :attribute_references,
               :custom_save_block,
               :data_collection_finalized=,
               :dependency_attributes,
               :targeted?,
               :parent,
               :parent_inventory_collections,
               :parent_inventory_collections=,
               :references,
               :transitive_dependency_attributes,
               :to => :inventory_collection

      def initialize(inventory_collection, indexed_inventory_collections, associations_hash)
        @inventory_collection          = inventory_collection
        @indexed_inventory_collections = indexed_inventory_collections
        @associations_hash             = associations_hash
      end

      def scan!
        # Scan InventoryCollection InventoryObjects and store the results inside of the InventoryCollection
        data.each do |inventory_object|
          scan_inventory_object!(inventory_object)
        end

        # Scan InventoryCollection skeletal data
        inventory_collection.skeletal_primary_index.each_value do |inventory_object|
          scan_inventory_object!(inventory_object)
        end

        build_parent_inventory_collections!
        scan_all_manager_uuids_scope!

        # Mark InventoryCollection as finalized aka. scanned
        self.data_collection_finalized = true
      end

      private

      def scan_all_manager_uuids_scope!
        return if all_manager_uuids_scope.nil?

        all_manager_uuids_scope.each do |scope|
          scope.each_value do |value|
            scan_all_manager_uuids_scope_attribute!(value)
          end
        end
      end

      def build_parent_inventory_collections!
        if parent_inventory_collections.nil?
          build_parent_inventory_collection!
        else
          # We can't figure out what immediate parent is, we'll add parent_inventory_collections as dependencies
          parent_inventory_collections.each { |ic_name| add_parent_inventory_collection_dependency!(ic_name) }
        end

        return if parent_inventory_collections.blank?

        # Transform InventoryCollection object names to actual objects
        self.parent_inventory_collections = parent_inventory_collections.map { |x| load_inventory_collection_by_name(x) }
      end

      def build_parent_inventory_collection!
        return unless supports_building_inventory_collection?

        if association.present? && parent.present? && associations_hash[association].present?
          # Add immediate parent IC as dependency
          add_parent_inventory_collection_dependency!(associations_hash[association])
          # Add root IC in parent_inventory_collections
          self.parent_inventory_collections = [find_parent_inventory_collection(associations_hash, inventory_collection.association)]
        end
      end

      def supports_building_inventory_collection?
        # Don't try to introspect ICs with custom query or saving code
        return if arel.present? || custom_save_block.present?
        # We support :parent_inventory_collections only for targeted mode, where all ICs are present
        return unless targeted?

        true
      end

      def add_parent_inventory_collection_dependency!(ic_name)
        ic = load_inventory_collection_by_name(ic_name)
        (dependency_attributes[:__parent_inventory_collections] ||= Set.new) << ic if ic
      end

      def find_parent_inventory_collection(hash, name)
        if hash[name]
          find_parent_inventory_collection(hash, hash[name])
        else
          name
        end
      end

      def load_inventory_collection_by_name(name)
        ic = indexed_inventory_collections[name]
        if ic.nil?
          raise "Can't find InventoryCollection :#{name} referenced from #{inventory_collection}" if targeted?
        end
        ic
      end

      def scan_inventory_object!(inventory_object)
        inventory_object.data.each do |key, value|
          if value.kind_of?(Array)
            value.each { |val| scan_inventory_object_attribute!(key, val) }
          else
            scan_inventory_object_attribute!(key, value)
          end
        end
      end

      def loadable?(value)
        inventory_object_lazy?(value) || inventory_object?(value)
      end

      def add_reference(value_inventory_collection, value)
        value_inventory_collection.add_reference(value.reference, :key => value.key)
      end

      def scan_all_manager_uuids_scope_attribute!(value)
        return unless loadable?(value)

        add_reference(value.inventory_collection, value)
        (dependency_attributes[:__all_manager_uuids_scope] ||= Set.new) << value.inventory_collection
      end

      def scan_inventory_object_attribute!(key, value)
        return unless loadable?(value)
        value_inventory_collection = value.inventory_collection

        # Storing attributes and their dependencies
        (dependency_attributes[key] ||= Set.new) << value_inventory_collection if value.dependency?

        # Storing a reference in the target inventory_collection, then each IC knows about all the references and can
        # e.g. load all the referenced uuids from a DB
        add_reference(value_inventory_collection, value)

        if inventory_object_lazy?(value)
          # Storing if attribute is a transitive dependency, so a lazy_find :key results in dependency
          transitive_dependency_attributes << key if value.transitive_dependency?
        end
      end
    end
  end
end
