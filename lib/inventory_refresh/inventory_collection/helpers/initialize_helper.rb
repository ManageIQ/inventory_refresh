require_relative "../helpers"

module InventoryRefresh
  class InventoryCollection
    module Helpers
      module InitializeHelper
        # @param association [Symbol] A Rails association callable on a :parent attribute is used for comparing with the
        #        objects in the DB, to decide if the InventoryObjects will be created/deleted/updated or used for obtaining
        #        the data from a DB, if a DB strategy is used. It returns objects of the :model_class class or its sub STI.
        # @param model_class [Class] A class of an ApplicationRecord model, that we want to persist into the DB or load from
        #        the DB.
        # @param name [Symbol] A unique name of the InventoryCollection under a Persister. If not provided, the :association
        #        attribute is used. If :association is nil as well, the :name will be inferred from the :model_class.
        # @param parent [ApplicationRecord] An ApplicationRecord object that has a callable :association method returning
        #        the objects of a :model_class.
        def init_basic_properties(association, model_class, name, parent)
          @association            = association
          @model_class            = model_class
          @name                   = name || association || model_class.to_s.demodulize.tableize
          @parent                 = parent || nil
        end

        # @param strategy [Symbol] A strategy of the InventoryCollection that will be used for saving/loading of the
        #        InventoryObject objects.
        #        Allowed strategies are:
        #         - nil => InventoryObject objects of the InventoryCollection will be saved to the DB, only these objects
        #                  will be referable from the other InventoryCollection objects.
        #         - :local_db_cache_all => Loads InventoryObject objects from the database, it loads all the objects that
        #                                  are a result of a [<:parent>.<:association>, :arel] taking
        #                                  first defined in this order. This strategy will not save any objects in the DB.
        #         - :local_db_find_references => Loads InventoryObject objects from the database, it loads only objects that
        #                                        were referenced by the other InventoryCollections using a filtered result
        #                                        of a [<:parent>.<:association>, :arel] taking first
        #                                        defined in this order. This strategy will not save any objects in the DB.
        #         - :local_db_find_missing_references => InventoryObject objects of the InventoryCollection will be saved to
        #                                                the DB. Then if we reference an object that is not present, it will
        #                                                load them from the db using :local_db_find_references strategy.
        # @param saver_strategy [Symbol] A strategy that will be used for InventoryCollection persisting into the DB.
        #        Allowed saver strategies are:
        #        - :default => Using Rails saving methods, this way is not safe to run in multiple workers concurrently,
        #          since it will lead to non consistent data.
        #        - :batch => Using batch SQL queries, this way is not safe to run in multiple workers
        #          concurrently, since it will lead to non consistent data.
        #        - :concurrent_safe_batch => It uses atomic upsert to avoid data duplication and it uses timestamp based
        #          atomic checks to avoid new data being overwritten by the the old data. The upsert/update queries are
        #          executed as batched SQL queries, instead of sending 1 query per record.
        # @param retention_strategy [Symbol] A retention strategy for this collection. Allowed values are:
        #        - :destroy => Will destroy the inactive records.
        #        - :archive => Will archive the inactive records by setting :archived_at timestamp.
        # @param delete_method [Symbol] A delete method that will be used for deleting of the InventoryObject, if the
        #        object is marked for deletion. A default is :destroy, the instance method must be defined on the
        #        :model_class.
        def init_strategies(strategy, saver_strategy, retention_strategy, delete_method)
          @saver_strategy     = process_saver_strategy(saver_strategy)
          @strategy           = process_strategy(strategy)
          @retention_strategy = process_retention_strategy(retention_strategy)
          @delete_method      = delete_method || :destroy
        end

        # @param manager_ref [Array] Array of Symbols, that are keys of the InventoryObject's data, inserted into this
        #        InventoryCollection. Using these keys, we need to be able to uniquely identify each of the InventoryObject
        #        objects inside.
        # @param manager_ref_allowed_nil [Array] Array of symbols having manager_ref columns, that are a foreign key an can
        #        be nil. Given the table are shared by many providers, it can happen, that the table is used only partially.
        #        Then it can happen we want to allow certain foreign keys to be nil, while being sure the referential
        #        integrity is not broken. Of course the DB Foreign Key can't be created in this case, so we should try to
        #        avoid this usecase by a proper modeling.
        #        Note that InventoryObject's data has to be build with <foreign_key> => nil, it means that key cannot be missing!
        # @param secondary_refs [Hash] TODO
        def init_references(manager_ref, manager_ref_allowed_nil, secondary_refs)
          @manager_ref             = manager_ref || %i(ems_ref)
          @manager_ref_allowed_nil = manager_ref_allowed_nil || []
          @secondary_refs          = secondary_refs || {}
        end

        # @param all_manager_uuids [Array] Array of all manager_uuids of the InventoryObjects. With the :targeted true,
        #        having this parameter defined will invoke only :delete_method on a complement of this set, making sure
        #        the DB has only this set of data after. This :attribute serves for deleting of top level
        #        InventoryCollections, i.e. InventoryCollections having parent_inventory_collections nil. The deleting of
        #        child collections is already handled by the scope of the parent_inventory_collections and using Rails
        #        :dependent => :destroy,
        # @param all_manager_uuids_scope [Array] A scope limiting the :all_manager_uuids parameter. E.g. we can send
        #        all_manager_uuids for 1 region, leading to delete a complement of the entities just under that 1
        #        region.
        #        If all_manager_uuids_scope is used with :all_manager_uuids => nil, it will do delete_complement of the
        #        scope itself. E.g. sending a list of all active regions, we will delete complement entities not
        #        belonging to those regions.
        #        Example:
        #          :all_manager_uuids       => [{:source_ref => x}, {:source_ref => y}],
        #          :all_manager_uuids_scope => [{:region => regions.lazy_find(X)}, {:region => regions.lazy_find(Y)}]
        #
        #        Will cause deletion/archival or all entities that don't have source_ref "x" or "y", but only under
        #        regions X and Y.
        # @param all_manager_uuids_timestamp [String] A timestamp in UTC marking a time before we collected all of the
        #        all_manager_uuids. Meaning we won't be archiving any newer entities.
        def init_all_manager_uuids(all_manager_uuids, all_manager_uuids_scope, all_manager_uuids_timestamp)
          # TODO(lsmola) Should we refactor this to use references too?
          @all_manager_uuids           = all_manager_uuids
          @all_manager_uuids_scope     = all_manager_uuids_scope
          @all_manager_uuids_timestamp = all_manager_uuids_timestamp
        end

        # @param dependency_attributes [Hash] Manually defined dependencies of this InventoryCollection. We can use this
        #        by manually place the InventoryCollection into the graph, to make sure the saving is invoked after the
        #        dependencies were saved. The dependencies itself are InventoryCollection objects. For a common use-cases
        #        we do not need to define dependencies manually, since those are inferred automatically by scanning of the
        #        data.
        #
        #        Example:
        #          :dependency_attributes => {
        #            :orchestration_stacks           => [collections[:orchestration_stacks]],
        #            :orchestration_stacks_resources => [collections[:orchestration_stacks_resources]]
        #          }
        #        This example is used in Example2 of the <param custom_save_block> and it means that our :custom_save_block
        #        will be invoked after the InventoryCollection :orchestration_stacks and :orchestration_stacks_resources
        #        are saved.
        # @param parent_inventory_collections [Array] Array of symbols having a name pointing to the
        #        InventoryRefresh::InventoryCollection objects, that serve as parents to this InventoryCollection. There are
        #        several scenarios to consider, when deciding if InventoryCollection has parent collections, see the example.
        #
        #        Example:
        #          taking inventory collections :vms and :disks (local disks), if we write that:
        #          inventory_collection = InventoryCollection.new({
        #                       :model_class                 => ::Disk,
        #                       :association                 => :disks,
        #                       :manager_ref                 => [:vm, :location]
        #                       :parent_inventory_collection => [:vms],
        #                     })
        #
        #          Then the decision for having :parent_inventory_collection => [:vms] was probably driven by these
        #          points:
        #          1. We can get list of all disks only by doing SQL query through the parent object (so there will be join
        #             from vms to disks table).
        #          2. There is no API query for getting all disks from the provider API, we get them inside VM data, or as
        #             a Vm subquery
        #          3. Part of the manager_ref of the IC is the VM object (foreign key), so the disk's location is unique
        #             only under 1 Vm. (In current models, this modeled going through Hardware model)
        #          4. In targeted refresh, we always expect that each Vm will be saved with all its disks.
        #
        #          Then having the above points, adding :parent_inventory_collection => [:vms], will bring these
        #          implications:
        #          1. By archiving/deleting Vm, we can no longer see the disk, because those were owned by the Vm. Any
        #             archival/deletion of the Disk model, must be then done by cascade delete/hooks logic.
        #          2. Having Vm as a parent ensures we always process it first. So e.g. when providing no Vms for saving
        #             we would have no graph dependency (no data --> no edges --> no dependencies) and Disk could be
        #             archived/removed before the Vm, while we always want to archive the VM first.
        #          3. For targeted refresh, we always expect that all disks are saved with a VM. So for targeting :disks,
        #             we are not using #manager_uuids attribute, since the scope is "all disks of all targeted VMs", so we
        #             always use #manager_uuids of the parent. (that is why :parent_inventory_collections and
        #             :manager_uuids are mutually exclusive attributes)
        #          4. For automatically building the #targeted_arel query, we need the parent to know what is the root node.
        #             While this information can be introspected from the data, it creates a scope for create&update&delete,
        #             which means it has to work with no data provided (causing delete all). So with no data we cannot
        #             introspect anything.
        def init_ic_relations(dependency_attributes, parent_inventory_collections = nil)
          @dependency_attributes        = dependency_attributes || {}
          @dependees                    = Set.new
          @parent_inventory_collections = parent_inventory_collections
        end

        # @param complete [Boolean] By default true, :complete is marking we are sending a complete dataset and therefore
        #        we can create/update/delete the InventoryObject objects. If :complete is false we will only do
        #        create/update without delete.
        # @param create_only [Boolean] TODO
        # @param check_changed [Boolean] By default true. If true, before updating the InventoryObject, we call Rails
        #        'changed?' method. This can optimize speed of updates heavily, but it can fail to recognize the change for
        #        e.g. Ancestry and Relationship based columns. If false, we always update the InventoryObject.
        # @param update_only [Boolean] By default false. If true we only update the InventoryObject objects, if false we do
        #        create/update/delete.
        # @param use_ar_object [Boolean] True or False. Whether we need to initialize AR object as part of the saving
        #        it's needed if the model have special setters, serialize of columns, etc. This setting is relevant only
        #        for the batch saver strategy.
        # @param targeted [Boolean] True if the collection is targeted, in that case it will be leveraging :manager_uuids
        #        :parent_inventory_collections and :targeted_arel to save a subgraph of a data.
        def init_flags(complete, create_only, check_changed,
                       update_only, use_ar_object, targeted,
                       assert_graph_integrity)
          @complete               = complete.nil? ? true : complete
          @create_only            = create_only.nil? ? false : create_only
          @check_changed          = check_changed.nil? ? true : check_changed
          @saved                  = false
          @update_only            = update_only.nil? ? false : update_only
          @use_ar_object          = use_ar_object || false
          @targeted               = !!targeted
          @assert_graph_integrity = assert_graph_integrity.nil? ? true : assert_graph_integrity
        end

        # @param attributes_blacklist [Array] Attributes we do not want to include into saving. We cannot blacklist an
        #        attribute that is needed for saving of the object.
        #        Note: attributes_blacklist is also used for internal resolving of the cycles in the graph.
        #
        #        In the Example2 of the <param custom_save_block>, we have a custom saving code, that saves a :parent
        #        attribute of the OrchestrationStack. That means we don't want that attribute saved as a part of
        #        InventoryCollection for OrchestrationStack, so we would set :attributes_blacklist => [:parent]. Then the
        #        :parent will be ignored while saving.
        # @param attributes_whitelist [Array] Same usage as the :attributes_blacklist, but defining full set of attributes
        #        that should be saved. Attributes that are part of :manager_ref and needed validations are automatically
        #        added.
        # @param inventory_object_attributes [Array] Array of attribute names that will be exposed as readers/writers on the
        #        InventoryObject objects inside.
        #
        #        Example: Given
        #                   inventory_collection = InventoryCollection.new({
        #                      :model_class                 => ::Vm,
        #                      :arel                        => @ems.vms,
        #                      :inventory_object_attributes => [:name, :label]
        #                    })
        #        And building the inventory_object like:
        #          inventory_object = inventory_collection.build(:ems_ref => "vm1", :name => "vm1")
        #        We can use inventory_object_attributes as setters and getters:
        #          inventory_object.name = "Name"
        #          inventory_object.label = inventory_object.name
        #        Which would be equivalent to less nicer way:
        #          inventory_object[:name] = "Name"
        #          inventory_object[:label] = inventory_object[:name]
        #        So by using inventory_object_attributes, we will be guarding the allowed attributes and will have an
        #        explicit list of allowed attributes, that can be used also for documentation purposes.
        # @param batch_extra_attributes [Array] Array of symbols marking which extra attributes we want to store into the
        #        db. These extra attributes might be a product of :use_ar_object assignment and we need to specify them
        #        manually, if we want to use a batch saving strategy and we have models that populate attributes as a side
        #        effect.
        def init_model_attributes(attributes_blacklist, attributes_whitelist,
                                  inventory_object_attributes, batch_extra_attributes)
          @attributes_blacklist             = Set.new
          @attributes_whitelist             = Set.new
          @batch_extra_attributes           = batch_extra_attributes || []
          @inventory_object_attributes      = inventory_object_attributes
          @internal_attributes              = %i(__feedback_edge_set_parent __parent_inventory_collections __all_manager_uuids_scope)
          @transitive_dependency_attributes = Set.new

          blacklist_attributes!(attributes_blacklist) if attributes_blacklist.present?
          whitelist_attributes!(attributes_whitelist) if attributes_whitelist.present?
        end

        def init_storages
          @data_storage       = ::InventoryRefresh::InventoryCollection::DataStorage.new(self, @secondary_refs)
          @references_storage = ::InventoryRefresh::InventoryCollection::ReferencesStorage.new(index_proxy)
        end

        # @param arel [ActiveRecord::Associations::CollectionProxy|Arel::SelectManager] Instead of :parent and :association
        #        we can provide Arel directly to say what records should be compared to check if InventoryObject will be
        #        doing create/update/delete.
        #
        #        Example:
        #        for a targeted refresh, we want to delete/update/create only a list of vms specified with a list of
        #        ems_refs:
        #            :arel => manager.vms.where(:ems_ref => manager_refs)
        #        Then we want to do the same for the hardwares of only those vms:
        #             :arel => manager.hardwares.joins(:vm_or_template).where(
        #               'vms' => {:ems_ref => manager_refs}
        #             )
        #        And etc. for the other Vm related records.
        # @param targeted_arel [Proc] A callable block that receives this InventoryCollection as a first argument. In there
        #        we can leverage a :parent_inventory_collections or :manager_uuids to limit the query based on the
        #        manager_uuids available.
        #        Example:
        #          targeted_arel = lambda do |inventory_collection|
        #            # Getting ems_refs of parent :vms and :miq_templates
        #            manager_uuids = inventory_collection.parent_inventory_collections.collect(&:manager_uuids).flatten
        #            inventory_collection.db_collection_for_comparison.hardwares.joins(:vm_or_template).where(
        #              'vms' => {:ems_ref => manager_uuids}
        #            )
        #          end
        #
        #          inventory_collection = InventoryCollection.new({
        #                                   :model_class                 => ::Hardware,
        #                                   :association                 => :hardwares,
        #                                   :parent_inventory_collection => [:vms, :miq_templates],
        #                                   :targeted_arel               => targeted_arel,
        #                                 })
        def init_arels(arel, targeted_arel)
          @arel                   = arel
          @targeted_arel          = targeted_arel
        end

        # @param custom_save_block [Proc] A custom lambda/proc for persisting in the DB, for cases where it's not enough
        #        to just save every InventoryObject inside by the defined rules and default saving algorithm.
        #
        #        Example1 - saving SomeModel in my own ineffective way :-) :
        #
        #            custom_save = lambda do |_ems, inventory_collection|
        #              inventory_collection.each |inventory_object| do
        #                hash = inventory_object.attributes # Loads possible dependencies into saveable hash
        #                obj = SomeModel.find_by(:attr => hash[:attr]) # Note: doing find_by for many models produces N+1
        #                                                              # queries, avoid this, this is just a simple example :-)
        #                obj.update_attributes(hash) if obj
        #                obj ||= SomeModel.create(hash)
        #                inventory_object.id = obj.id # If this InventoryObject is referenced elsewhere, we need to store its
        #                                               primary key back to the InventoryObject
        #             end
        #
        #        Example2 - saving parent OrchestrationStack in a more effective way, than the default saving algorithm can
        #        achieve. Ancestry gem requires an ActiveRecord object for association and is not defined as a proper
        #        ActiveRecord association. That leads in N+1 queries in the default saving algorithm, so we can do better
        #        with custom saving for now. The InventoryCollection is defined as a custom dependencies processor,
        #        without its own :model_class and InventoryObjects inside:
        #
        #            InventoryRefresh::InventoryCollection.new({
        #              :association       => :orchestration_stack_ancestry,
        #              :custom_save_block => orchestration_stack_ancestry_save_block,
        #              :dependency_attributes => {
        #                :orchestration_stacks           => [collections[:orchestration_stacks]],
        #                :orchestration_stacks_resources => [collections[:orchestration_stacks_resources]]
        #              }
        #            })
        #
        #        And the lambda is defined as:
        #
        #            orchestration_stack_ancestry_save_block = lambda do |_ems, inventory_collection|
        #              stacks_inventory_collection = inventory_collection.dependency_attributes[:orchestration_stacks].try(:first)
        #
        #              return if stacks_inventory_collection.blank?
        #
        #              stacks_parents = stacks_inventory_collection.data.each_with_object({}) do |x, obj|
        #                parent_id = x.data[:parent].load.try(:id)
        #                obj[x.id] = parent_id if parent_id
        #              end
        #
        #              model_class = stacks_inventory_collection.model_class
        #
        #              stacks_parents_indexed = model_class
        #                                         .select([:id, :ancestry])
        #                                         .where(:id => stacks_parents.values).find_each.index_by(&:id)
        #
        #              model_class
        #                .select([:id, :ancestry])
        #                .where(:id => stacks_parents.keys).find_each do |stack|
        #                parent = stacks_parents_indexed[stacks_parents[stack.id]]
        #                stack.update_attribute(:parent, parent)
        #              end
        #            end
        # @param custom_reconnect_block [Proc] A custom lambda for reconnect logic of previously disconnected records
        #
        #        Example - Reconnect disconnected Vms
        #            InventoryRefresh::InventoryCollection.new({
        #              :association            => :orchestration_stack_ancestry,
        #              :custom_reconnect_block => vms_custom_reconnect_block,
        #            })
        #
        #        And the lambda is defined as:
        #
        #            vms_custom_reconnect_block = lambda do |inventory_collection, inventory_objects_index, attributes_index|
        #              inventory_objects_index.each_slice(1000) do |batch|
        #                Vm.where(:ems_ref => batch.map(&:second).map(&:manager_uuid)).each do |record|
        #                  index = inventory_collection.object_index_with_keys(inventory_collection.manager_ref_to_cols, record)
        #
        #                  # We need to delete the record from the inventory_objects_index and attributes_index, otherwise it
        #                  # would be sent for create.
        #                  inventory_object = inventory_objects_index.delete(index)
        #                  hash             = attributes_index.delete(index)
        #
        #                  record.assign_attributes(hash.except(:id, :type))
        #                  if !inventory_collection.check_changed? || record.changed?
        #                    record.save!
        #                    inventory_collection.store_updated_records(record)
        #                  end
        #
        #                  inventory_object.id = record.id
        #                end
        #              end
        def init_custom_procs(custom_save_block, custom_reconnect_block)
          @custom_save_block      = custom_save_block
          @custom_reconnect_block = custom_reconnect_block
        end

        # @param default_values [Hash] A hash of an attributes that will be added to every inventory object created by
        #        inventory_collection.build(hash)
        #
        #        Example: Given
        #          inventory_collection = InventoryCollection.new({
        #            :model_class    => ::Vm,
        #            :arel           => @ems.vms,
        #            :default_values => {:ems_id => 10}
        #          })
        #        And building the inventory_object like:
        #            inventory_object = inventory_collection.build(:ems_ref => "vm_1", :name => "vm1")
        #        The inventory_object.data will look like:
        #            {:ems_ref => "vm_1", :name => "vm1", :ems_id => 10}
        def init_data(default_values)
          @default_values = default_values || {}
        end

        def init_changed_records_stats
          @created_records = []
          @updated_records = []
          @deleted_records = []
        end

        # Processes passed saver strategy
        #
        # @param saver_strategy [Symbol] Passed saver strategy
        # @return [Symbol] Returns back the passed strategy if supported, or raises exception
        def process_saver_strategy(saver_strategy)
          return :default unless saver_strategy

          saver_strategy = saver_strategy.to_sym
          case saver_strategy
          when :default, :batch, :concurrent_safe_batch
            saver_strategy
          else
            raise "Unknown InventoryCollection saver strategy: :#{saver_strategy}, allowed strategies are "\
              ":default, :batch and :concurrent_safe_batch"
          end
        end

        # Processes passed strategy, modifies :data_collection_finalized and :saved attributes for db only strategies
        #
        # @param strategy_name [Symbol] Passed saver strategy
        # @return [Symbol] Returns back the passed strategy if supported, or raises exception
        def process_strategy(strategy_name)
          self.data_collection_finalized = false

          return unless strategy_name

          strategy_name = strategy_name.to_sym
          case strategy_name
          when :local_db_cache_all
            self.data_collection_finalized = true
            self.saved = true
          when :local_db_find_references
            self.saved = true
          when :local_db_find_missing_references
            nil
          else
            raise "Unknown InventoryCollection strategy: :#{strategy_name}, allowed strategies are :local_db_cache_all, "\
              ":local_db_find_references and :local_db_find_missing_references."
          end
          strategy_name
        end

        # Processes passed retention strategy
        #
        # @param retention_strategy [Symbol] Passed retention strategy
        # @return [Symbol] Returns back the passed strategy if supported, or raises exception
        def process_retention_strategy(retention_strategy)
          return unless retention_strategy

          retention_strategy = retention_strategy.to_sym
          case retention_strategy
          when :destroy, :archive
            retention_strategy
          else
            raise "Unknown InventoryCollection retention strategy: :#{retention_strategy}, allowed strategies are "\
              ":destroy and :archive"
          end
        end
      end
    end
  end
end
