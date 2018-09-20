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

          # TODO(lsmola) build parent inventory collections automatically here

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
      delegate :association,
               :attribute_references,
               :data_collection_finalized=,
               :dependency_attributes,
               :targeted_scope,
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

          if targeted? && parent_inventory_collections.blank?
            # We want to track what manager_uuids we should query from a db, for the targeted refresh
            targeted_scope << inventory_object.reference
          end
        end

        build_parent_inventory_collections!

        # Mark InventoryCollection as finalized aka. scanned
        self.data_collection_finalized = true
      end

      private

      def build_parent_inventory_collections!
        if parent_inventory_collections.blank?
          if association.present? && parent.present? && associations_hash[association].present?
            # We want to add immediate parent (parent in a through relation) as a dependency too
            add_as_parent_inventory_collection_dependency(load_inventory_collection_by_name(associations_hash[association]))

            parent_inventory_collection = find_parent_inventory_collection(associations_hash, inventory_collection.association)
            (self.parent_inventory_collections ||= []) << load_inventory_collection_by_name(parent_inventory_collection)
          end
        else
          self.parent_inventory_collections = parent_inventory_collections.map { |x| load_inventory_collection_by_name(x) }
        end

        return if parent_inventory_collections.blank?

        parent_inventory_collections.each do |ic|
          add_as_parent_inventory_collection_dependency(ic)
        end
      end

      def add_as_parent_inventory_collection_dependency(ic)
        (dependency_attributes[:__parent_inventory_collections] ||= Set.new) << ic
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
          raise "Can't find InventoryCollection :#{name} referenced from #{inventory_collection}"
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

      def scan_inventory_object_attribute!(key, value)
        return if !inventory_object_lazy?(value) && !inventory_object?(value)
        value_inventory_collection = value.inventory_collection

        # Storing attributes and their dependencies
        (dependency_attributes[key] ||= Set.new) << value_inventory_collection if value.dependency?

        # Storing a reference in the target inventory_collection, then each IC knows about all the references and can
        # e.g. load all the referenced uuids from a DB
        value_inventory_collection.add_reference(value.reference, :key => value.key)

        if inventory_object_lazy?(value)
          # Storing if attribute is a transitive dependency, so a lazy_find :key results in dependency
          transitive_dependency_attributes << key if value.transitive_dependency?
        end
      end
    end
  end
end
