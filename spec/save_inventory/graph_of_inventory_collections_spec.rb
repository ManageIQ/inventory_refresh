require_relative 'spec_helper'
require_relative '../helpers/spec_parsed_data'
require_relative '../helpers/test_persister'

describe InventoryRefresh::SaveInventory do
  include SpecHelper
  include SpecParsedData

  ######################################################################################################################
  #
  # Testing SaveInventory for general graph of the InventoryCollection dependencies, testing that relations
  # are saved correctly for a testing set of InventoryCollections whose dependencies look like:
  #
  # 1. Example, cycle is stack -> stack
  #
  # edge Stack -> Stack is created by (:parent => @persister.orchestration_stacks.lazy_find(stack_ems_ref)) meaning Stack
  #   depends on Stack through :parent attribute
  #
  # edge Resource -> Stack is created by (:stack => @persister.orchestration_stacks.lazy_find(stack_ems_ref)) meaning
  #   Resource depends on Stack through :stack attribute
  #
  #              +-----------------------+                                  +-----------------------+
  #              |                       |                                  |                       |
  #              |                       |                                  |                       |
  #              |                       |                                  |                       |
  #              |         Stack         |                                  |         Stack         |
  #              |                       <-----+                            | blacklist: [:parent]  |
  #              |                       |     |                            |                       <---------+
  #              |              :parent  |     |                            |                       |         |
  #              +---^--------------+----+     |    to DAG ->               +---^----------------^--+         |
  #                  |              |          |                                |                |            |
  #                  |              |          |                                |                |            |
  #  +---------------+-------+      +----------+                +---------------+-------+     +--+------------+-------+
  #  |            :stack     |                                  |            :stack     |     | :parent    :internal  |
  #  |                       |                                  |                       |     |                       |
  #  |                       |                                  |                       |     |                       |
  #  |         Resource      |                                  |         Resource      |     |         Stack         |
  #  |                       |                                  |                       |     | whitelist: [:parent]  |
  #  |                       |                                  |                       |     |                       |
  #  |                       |                                  |                       |     |                       |
  #  +-----------------------+                                  +-----------------------+     +-----------------------+
  #
  # 2. Example, cycle is stack -> resource -> stack
  #
  # edge Stack -> Resource is created by
  #   (:parent => @persister.orchestration_stacks_resources.lazy_find(resource_ems_ref, :key => :stack)) meaning Stack
  #   depends on Resource through :parent attribute. Due to the usage of :key => :stack, Stack actually depends on
  #   Resource that has :stack attribute saved.
  #
  # edge Resource -> Stack is created by (:stack => @persister.orchestration_stacks.lazy_find(stack_ems_ref)) meaning
  #   Resource depends on Stack through :stack attribute
  #
  #  +-----------------------+                                  +-----------------------+
  #  |                       |                                  |                       |
  #  |                       |                                  |                       |
  #  |                       |                                  |                       |
  #  |         Stack         |                                  |         Stack         |
  #  |                       |                                  | blacklist: [:parent]  |
  #  |                       |                                  |                       |
  #  |              :parent  |                                  |                       <--+
  #  +---^-------------+-----+                                  +---------------^-------+  |
  #      |             |               to DAG ->                                |          |
  #      |             |                                                        |          |
  #      |             |                                        +---------------+-------+  |
  #  +---+-------------v-----+                                  |            :stack     |  |
  #  |   :stack              |                                  |                       |  |
  #  |                       |                                  |                       |  |
  #  |                       |                                  |         Resource      |  |
  #  |        Resource       |                                  |                       |  |
  #  |                       |                                  |                       |  |
  #  |                       |                                  |                       |  |
  #  |                       |                                  +----^------------------+  |
  #  +-----------------------+                                       |                     |
  #                                                                  |                     |
  #                                                             +----+------------------+  |
  #                                                             | :parent      :internal+--+
  #                                                             |                       |
  #                                                             |                       |
  #                                                             |         Stack         |
  #                                                             | whitelist: [:parent]  |
  #                                                             |                       |
  #                                                             |                       |
  #                                                             +-----------------------+
  #
  # 3. Example, cycle is network_port -> stack -> resource -> stack
  #
  # edge Stack -> Resource is created by
  #   (:parent => @persister.orchestration_stacks_resources.lazy_find(resource_ems_ref, :key => :stack)) meaning Stack
  #   depends on Resource through :parent attribute. Due to the usage of :key => :stack, Stack actually depends on
  #   Resource that has :stack attribute saved.
  #
  # edge Resource -> Stack is created by (:stack => @persister.orchestration_stacks.lazy_find(stack_ems_ref)) meaning
  #   Resource depends on Stack through :stack attribute
  #
  # edge NetworkPort -> Stack is created by
  #   (:device => @persister.orchestration_stacks.lazy_find(stack_ems_ref, :key => :parent)) meaning that NetworkPort
  #   depends on Stack through :device polymorphic attribute. Due to the usage of :key => :parent, NetworkPort actually
  #   depends on Stack with :parent attribute saved.
  #
  #   So in this case the DAG conversion also needs to change the edge which was NetworkPort -> Stack(with blacklist)
  #   to NetworkPort -> Stack(with whitelist)
  #
  #  +-----------------------+     +-----------------------+
  #  |                       |     |                       |
  #  |                       |     |                       |
  #  |                       |     |                       |
  #  |       NetworkPort     |     |         Stack         |
  #  |                       |  +-->                       |
  #  |                       |  |  |                       |
  #  |         :device       |  |  |              :parent  |
  #  +--------------+--------+  |  +---^-------------+-----+
  #                 |           |      |             |
  #                 +-----------+      |             |
  #                                    |             |
  #                                +---+-------------v-----+
  #                                |   :stack              |
  #                                |                       |
  #                                |                       |
  #                                |        Resource       |
  #                                |                       |
  #                                |                       |
  #                                |                       |
  #                                +-----------------------+
  #
  #                          to DAG
  #                             |
  #                             |
  #                             v
  #
  #  +-----------------------+     +-----------------------+
  #  |                       |     |                       |
  #  |                       |     |                       |
  #  |                       |     |                       |
  #  |       NetworkPort     |     |         Stack         |
  #  |                       |     | blacklist: [:parent]  |
  #  |                       |     |                       |
  #  |        :device        |     |                       <--+
  #  +-----------+-----------+     +---------------^-------+  |
  #              |                                 |          |
  #              |                                 |          |
  #              +--------------+  +---------------+-------+  |
  #                             |  |            :stack     |  |
  #                             |  |                       |  |
  #                             |  |                       |  |
  #                             |  |         Resource      |  |
  #                             |  |                       |  |
  #                             |  |                       |  |
  #                             |  |                       |  |
  #                             |  +----^------------------+  |
  #                             |       |                     |
  #                             |       |                     |
  #                             |  +----+------------------+  |
  #                             |  | :parent      :internal+--+
  #                             |  |                       |
  #                             |  |                       |
  #                             +-->         Stack         |
  #                                | whitelist: [:parent]  |
  #                                |                       |
  #                                |                       |
  #                                +-----------------------+
  #
  # 4. Example, cycle is network_port -> network_port -> stack -> resource -> stack
  #
  # edge Stack -> Resource is created by
  #   (:parent => @persister.orchestration_stacks_resources.lazy_find(resource_ems_ref, :key => :stack)) meaning Stack
  #   depends on Resource through :parent attribute. Due to the usage of :key => :stack, Stack actually depends on
  #   Resource that has :stack attribute saved.
  #
  # edge Resource -> Stack is created by (:stack => @persister.orchestration_stacks.lazy_find(stack_ems_ref)) meaning
  #   Resource depends on Stack through :stack attribute
  #
  # edge NetworkPort -> NetworkPort is created by (:device => @persister.network_ports.lazy_find(network_port_ems_ref))
  #   meaning that NetworkPort depends on NetworkPort through :device polymorphic attribute
  #
  # edge NetworkPort -> Stack is created by
  #   (:device => @persister.orchestration_stacks.lazy_find(stack_ems_ref, :key => :parent)) meaning that NetworkPort
  #   depends on Stack through :device polymorphic attribute. Due to the usage of :key => :parent, NetworkPort actually
  #   depends on Stack with :parent attribute saved.
  #
  #   So in this case the DAG conversion also needs to change the edge which was NetworkPort(with whitelist) ->
  #   Stack(with blacklist) to NetworkPort(with whitelist) -> Stack(with whitelist)
  #
  #  +-----------------------+     +-----------------------+
  #  |                       |     |                       |
  #  |                       |     |                       |
  #  |                       |     |                       |
  #  |       NetworkPort     |     |         Stack         |
  #  |                       |  +-->                       |
  #  |                       |  |  |                       |
  #  |         :device       |  |  |              :parent  |
  #  +---------+-^--+--------+  |  +---^-------------+-----+
  #            | |  |           |      |             |
  #            +-+  +-----------+      |             |
  #                                    |             |
  #                                +---+-------------v-----+
  #                                |   :stack              |
  #                                |                       |
  #                                |                       |
  #                                |        Resource       |
  #                                |                       |
  #                                |                       |
  #                                |                       |
  #                                +-----------------------+
  #
  #                          to DAG
  #                             |
  #                             |
  #                             v
  #
  #  +-----------------------+     +-----------------------+
  #  |                       |     |                       |
  #  |                       |     |                       |
  #  |                       |     |                       |
  #  |       NetworkPort     |     |         Stack         |
  #  |  blacklist: [:device] |     | blacklist: [:parent]  |
  #  |                       |     |                       |
  #  |                       |     |                       <--+
  #  +----^------^-----------+     +---------------^-------+  |
  #       |      |                                 |          |
  #       |      |                                 |          |
  #       |      | +------------+  +---------------+-------+  |
  #       |      | |            |  |            :stack     |  |
  #       |      | |            |  |                       |  |
  #  +----+------+-+---------+  |  |                       |  |
  #  |:internal :device      |  |  |         Resource      |  |
  #  |                       |  |  |                       |  |
  #  |                       |  |  |                       |  |
  #  |       NetworkPort     |  |  |                       |  |
  #  |  whitelist: [:device] |  |  +----^------------------+  |
  #  |                       |  |       |                     |
  #  |                       |  |       |                     |
  #  +-----------------------+  |  +----+------------------+  |
  #                             |  | :parent      :internal+--+
  #                             |  |                       |
  #                             |  |                       |
  #                             +-->         Stack         |
  #                                | whitelist: [:parent]  |
  #                                |                       |
  #                                |                       |
  #                                +-----------------------+
  #
  # 5. Example, cycle is network_port -> network_port using key
  #
  # The edge NetworkPort -> NetworkPort is created by
  #   :device => @persister.network_ports.lazy_find(network_port_ems_ref)
  #   and
  #   :device => @persister.network_ports.lazy_find(network_port_ems_ref, :key => :device)
  #   which creates an unsolvable cycle, since NetworkPort depends on NetworkPort with :device attribute saved, through
  #   :device attribute
  #
  #  +-----------------------+                 +-----------------------+
  #  |                       |                 |                       |
  #  |                       |                 |                       |
  #  |                       |                 |                       |
  #  |       NetworkPort     |                 |       NetworkPort     |
  #  |  blacklist: [:device] |                 |  blacklist: [:device] |
  #  |                       |                 |                       |
  #  |       :device         |                 |                       |
  #  +---------+--^----------+    to DAG ->    +------------------^----+
  #            |  |                                               |
  #            |  |                                               |
  #            +--+                                   +--+        |
  #                                                   |  |        |
  #                                                   |  |        |
  #                                            +------+--v--------+----+
  #                                            |    :device   :internal|
  #                                            |                       |
  #                                            |                       |
  #                                            |       NetworkPort     |
  #                                            |  whitelist: [:device] |
  #                                            |                       |
  #                                            |                       |
  #                                            +-----------------------+
  # We can see that the cycle just moved to NetworkPort(with whitelist), since the only way to solve this dependency
  # is to actually store records of the NetworkPort in a certain order with a custom saving method.
  #
  ######################################################################################################################

  let(:persister_class) { ::TestPersister }
  before do
    @ems         = FactoryBot.create(:ems_cloud)
    @ems_network = FactoryBot.create(:ems_network, :parent_manager => @ems)

    allow(@ems.class).to receive(:ems_type).and_return(:mock)
    @persister = persister_class.new(@ems, InventoryRefresh::TargetCollection.new(:manager => @ems))
  end

  context 'with empty DB' do
    it 'creates and updates a graph of InventoryCollections with cycle stack -> stack' do
      # Doing 2 times, to make sure we first create all records then update all records
      2.times do
        # Fill the InventoryCollections with data
        initialize_inventory_collections
        init_stack_data_with_stack_stack_cycle
        init_resource_data

        # Invoke the InventoryCollections saving
        InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

        # Assert saved data
        assert_full_inventory_collections_graph
      end
    end

    it 'creates and updates a graph of InventoryCollections with cycle stack -> resource -> stack, through resource :key' do
      # Doing 2 times, to make sure we first create all records then update all records
      2.times do
        # Fill the InventoryCollections with data
        initialize_inventory_collections
        init_stack_data_with_stack_resource_stack_cycle
        init_resource_data

        # Invoke the InventoryCollections saving
        InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

        # Assert saved data
        assert_full_inventory_collections_graph
      end
    end
  end

  context 'with empty DB and reversed InventoryCollections' do
    it 'creates and updates a graph of InventoryCollections with cycle stack -> stack' do
      # Doing 2 times, to make sure we first create all records then update all records
      2.times do
        # Fill the InventoryCollections with data
        initialize_inventory_collections(:reversed => true)
        init_stack_data_with_stack_stack_cycle
        init_resource_data

        # Invoke the InventoryCollections saving
        InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

        # Assert saved data
        assert_full_inventory_collections_graph
      end
    end

    it 'creates and updates a graph of InventoryCollections with cycle stack -> resource -> stack, through resource :key' do
      # Doing 2 times, to make sure we first create all records then update all records
      2.times do
        # Fill the InventoryCollections with data
        initialize_inventory_collections(:reversed => true)
        init_stack_data_with_stack_resource_stack_cycle
        init_resource_data

        # Invoke the InventoryCollections saving
        InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

        # Assert saved data
        assert_full_inventory_collections_graph
      end
    end
  end

  context 'with complex cycle' do
    it 'test network_port -> stack -> resource -> stack' do
      initialize_inventory_collections(:add_network_ports => true)

      init_stack_data_with_stack_resource_stack_cycle
      init_resource_data

      @persister.network_ports.build(
        network_port_data(1).merge(
          :device => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("1_11")[:ems_ref],
                                                               :key => :parent)
        )
      )
      @persister.network_ports.build(
        network_port_data(2).merge(
          :device => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("11_21")[:ems_ref],
                                                               :key => :parent)
        )
      )
      @persister.network_ports.build(
        network_port_data(3).merge(
          :device => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("12_22")[:ems_ref],
                                                               :key => :parent)
        )
      )

      # Invoke the InventoryCollections saving
      InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

      # Assert saved data
      assert_full_inventory_collections_graph

      network_port_1 = NetworkPort.find_by(:ems_ref => "network_port_ems_ref_1")
      network_port_2 = NetworkPort.find_by(:ems_ref => "network_port_ems_ref_2")
      network_port_3 = NetworkPort.find_by(:ems_ref => "network_port_ems_ref_3")

      orchestration_stack_0_1 = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_0_1")
      orchestration_stack_1_11 = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_1_11")
      orchestration_stack_1_12 = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_1_12")
      expect(network_port_1.device).to eq(orchestration_stack_0_1)
      expect(network_port_2.device).to eq(orchestration_stack_1_11)
      expect(network_port_3.device).to eq(orchestration_stack_1_12)
    end

    it 'test network_port -> stack -> resource -> stack reverted' do
      @persister.add_collection(:network_ports) do |builder|
        builder.add_properties(
          :model_class => NetworkPort,
          :parent      => @ems.network_manager,
        )
      end
      initialize_inventory_collections(:reversed => true)

      init_stack_data_with_stack_resource_stack_cycle
      init_resource_data

      @persister.network_ports.build(
        network_port_data(1).merge(
          :device => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("1_11")[:ems_ref],
                                                               :key => :parent)
        )
      )
      @persister.network_ports.build(
        network_port_data(2).merge(
          :device => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("11_21")[:ems_ref],
                                                               :key => :parent)
        )
      )
      @persister.network_ports.build(
        network_port_data(3).merge(
          :device => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("12_22")[:ems_ref],
                                                               :key => :parent)
        )
      )

      # Invoke the InventoryCollections saving
      InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)
      # Assert saved data
      assert_full_inventory_collections_graph

      network_port_1 = NetworkPort.find_by(:ems_ref => "network_port_ems_ref_1")
      network_port_2 = NetworkPort.find_by(:ems_ref => "network_port_ems_ref_2")
      network_port_3 = NetworkPort.find_by(:ems_ref => "network_port_ems_ref_3")

      orchestration_stack_0_1 = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_0_1")
      orchestration_stack_1_11 = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_1_11")
      orchestration_stack_1_12 = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_1_12")
      expect(network_port_1.device).to eq(orchestration_stack_0_1)
      expect(network_port_2.device).to eq(orchestration_stack_1_11)
      expect(network_port_3.device).to eq(orchestration_stack_1_12)
    end

    it "test network_port -> network_port through network_port's :device can't be converted to DAG" do
      # We are creating an unsolvable cycle, cause only option to save this data is writing a custom method, that
      # saved the data in a correct order. In this case, we would need to save this data by creating a tree of
      # data dependencies and saving it according to the tree.
      @persister.add_collection(:network_ports) do |builder|
        builder.add_properties(
          :model_class => NetworkPort,
          :parent      => @ems.network_manager,
        )
      end

      @persister.network_ports.build(
        network_port_data(1).merge(
          :device => @persister.network_ports.lazy_find(network_port_data(1)[:ems_ref])
        )
      )
      @persister.network_ports.build(
        network_port_data(2).merge(
          :device => @persister.network_ports.lazy_find(network_port_data(1)[:ems_ref],
                                                        :key => :device)
        )
      )

      # Invoke the InventoryCollections saving and check we raise an exception that a cycle was found, after we
      # attempted to remove the cycles.
      expect { InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections) }.to raise_error(/^Cycle from /)
    end

    it 'test network_port -> network_port -> stack -> resource -> stack' do
      # TODO(lmola) this test should pass, since there is not an unbreakable cycle, we should move only edge
      # network_port ->> stack to network_port -> stack_new. Now we move also edge created by untangling to cycle,
      # that was network_port -> network_port, then it's correctly network_port_new -> network_port, but then
      # the transitive edge check catch this and it's turned to network_port_new -> network_port_new, which is a
      # cycle again.
      # What this needs to be:
      #
      # It can happen, that one edge is transitive but other is not using the same relations:
      # So this is a transitive edge:
      #  :device => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("11_21")[:ems_ref],
      #                                                       :key => :parent)
      # And this is not:
      #  :device => @persister.network_ports.lazy_find(network_port_data(4)[:ems_ref])
      #
      # By correctly storing that :device is causing transitive edge only when pointing to
      # @persister.orchestration_stacks but not when pointing to @persister.network_ports, then we can transform the
      # edge correctly and this cycle is solvable.
      initialize_inventory_collections(:add_network_ports => true)

      init_stack_data_with_stack_resource_stack_cycle
      init_resource_data

      @persister.network_ports.build(
        network_port_data(1).merge(
          :device => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("1_11")[:ems_ref],
                                                               :key => :parent)
        )
      )
      @persister.network_ports.build(
        network_port_data(2).merge(
          :device => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("11_21")[:ems_ref],
                                                               :key => :parent)
        )
      )
      @persister.network_ports.build(
        network_port_data(3).merge(
          :device => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("12_22")[:ems_ref],
                                                               :key => :parent)
        )
      )
      @persister.network_ports.build(
        network_port_data(4).merge(
          :device => @persister.network_ports.lazy_find(network_port_data(3)[:ems_ref])
        )
      )
      @persister.network_ports.build(
        network_port_data(5).merge(
          :device => @persister.network_ports.lazy_find(network_port_data(4)[:ems_ref])
        )
      )
      @persister.network_ports.build(
        network_port_data(7).merge(
          :device => @persister.network_ports.lazy_find(network_port_data(7)[:ems_ref])
        )
      )

      # Invoke the InventoryCollections saving and check we raise an exception that a cycle was found, after we
      # attempted to remove the cycles.
      # TODO(lsmola) make this spec pass, by enhancing the logic around transitive edges
      expect { InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections) }.to raise_error(/^Cycle from /)
    end

    it 'test network_port -> stack -> resource -> stack and network_port -> resource -> stack -> resource -> stack ' do
      initialize_inventory_collections(:add_network_ports => true)

      init_stack_data_with_stack_resource_stack_cycle
      init_resource_data

      @persister.network_ports.build(
        network_port_data(1).merge(
          :device => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("1_11")[:ems_ref],
                                                               :key => :parent)
        )
      )
      @persister.network_ports.build(
        network_port_data(2).merge(
          :device => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("11_21")[:ems_ref],
                                                               :key => :parent)
        )
      )
      @persister.network_ports.build(
        network_port_data(3).merge(
          :device => @persister.orchestration_stacks_resources.lazy_find(orchestration_stack_data("12_22")[:ems_ref],
                                                                         :key => :stack)
        )
      )
      @persister.network_ports.build(
        network_port_data(4).merge(
          :device => @persister.orchestration_stacks_resources.lazy_find(orchestration_stack_data("12_22")[:ems_ref])
        )
      )

      # Invoke the InventoryCollections saving
      InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

      # Assert saved data
      assert_full_inventory_collections_graph

      network_port_1 = NetworkPort.find_by(:ems_ref => "network_port_ems_ref_1")
      network_port_2 = NetworkPort.find_by(:ems_ref => "network_port_ems_ref_2")
      network_port_3 = NetworkPort.find_by(:ems_ref => "network_port_ems_ref_3")
      network_port_4 = NetworkPort.find_by(:ems_ref => "network_port_ems_ref_4")

      orchestration_stack_0_1 = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_0_1")
      orchestration_stack_1_11 = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_1_11")
      orchestration_stack_1_12 = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_1_12")

      orchestration_resource_12_22 = OrchestrationStackResource.find_by(:ems_ref => "stack_ems_ref_12_22")

      expect(network_port_1.device).to eq(orchestration_stack_0_1)
      expect(network_port_2.device).to eq(orchestration_stack_1_11)
      expect(network_port_3.device).to eq(orchestration_stack_1_12)
      expect(network_port_4.device).to eq(orchestration_resource_12_22)
    end
  end

  context 'with the existing data in the DB' do
    it 'updates existing records with a graph of InventoryCollections with cycle stack -> stack' do
      # Create all relations directly in DB
      initialize_mocked_records
      # And check the relations are correct
      assert_full_inventory_collections_graph

      # Now we will update existing DB using SaveInventory
      # Fill the InventoryCollections with data
      initialize_inventory_collections
      init_stack_data_with_stack_stack_cycle
      init_resource_data

      # Invoke the InventoryCollections saving
      InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

      # Assert saved data
      assert_full_inventory_collections_graph

      # Check that we only updated the existing records
      orchestration_stack_0_1   = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_0_1")
      orchestration_stack_0_2   = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_0_2")
      orchestration_stack_1_11  = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_1_11")
      orchestration_stack_1_12  = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_1_12")
      orchestration_stack_11_21 = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_11_21")
      orchestration_stack_12_22 = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_12_22")
      orchestration_stack_12_23 = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_12_23")

      orchestration_stack_resource_1_11 = OrchestrationStackResource.find_by(
        :ems_ref => "stack_ems_ref_1_11"
      )
      orchestration_stack_resource_1_11_1 = OrchestrationStackResource.find_by(
        :ems_ref => "stack_resource_physical_resource_1_11_1"
      )
      orchestration_stack_resource_1_12 = OrchestrationStackResource.find_by(
        :ems_ref => "stack_ems_ref_1_12"
      )
      orchestration_stack_resource_1_12_1 = OrchestrationStackResource.find_by(
        :ems_ref => "stack_resource_physical_resource_1_12_1"
      )
      orchestration_stack_resource_11_21 = OrchestrationStackResource.find_by(
        :ems_ref => "stack_ems_ref_11_21"
      )
      orchestration_stack_resource_12_22 = OrchestrationStackResource.find_by(
        :ems_ref => "stack_ems_ref_12_22"
      )
      orchestration_stack_resource_12_23 = OrchestrationStackResource.find_by(
        :ems_ref => "stack_ems_ref_12_23"
      )

      expect(orchestration_stack_0_1).to eq(@orchestration_stack_0_1)
      expect(orchestration_stack_0_2).to eq(@orchestration_stack_0_2)
      expect(orchestration_stack_1_11).to eq(@orchestration_stack_1_11)
      expect(orchestration_stack_1_12).to eq(@orchestration_stack_1_12)
      expect(orchestration_stack_11_21).to eq(@orchestration_stack_11_21)
      expect(orchestration_stack_12_22).to eq(@orchestration_stack_12_22)
      expect(orchestration_stack_12_23).to eq(@orchestration_stack_12_23)

      expect(orchestration_stack_resource_1_11).to eq(@orchestration_stack_resource_1_11)
      expect(orchestration_stack_resource_1_11_1).to eq(@orchestration_stack_resource_1_11_1)
      expect(orchestration_stack_resource_1_12).to eq(@orchestration_stack_resource_1_12)
      expect(orchestration_stack_resource_1_12_1).to eq(@orchestration_stack_resource_1_12_1)
      expect(orchestration_stack_resource_11_21).to eq(@orchestration_stack_resource_11_21)
      expect(orchestration_stack_resource_12_22).to eq(@orchestration_stack_resource_12_22)
      expect(orchestration_stack_resource_12_23).to eq(@orchestration_stack_resource_12_23)
    end

    it 'updates existing records with a graph of InventoryCollections with cycle stack -> resource -> stack, through resource :key' do
      # Create all relations directly in DB
      initialize_mocked_records
      # And check the relations are correct
      assert_full_inventory_collections_graph

      # Now we will update existing DB using SaveInventory
      # Fill the InventoryCollections with data
      initialize_inventory_collections
      init_stack_data_with_stack_resource_stack_cycle
      init_resource_data

      # Invoke the InventoryCollections saving
      InventoryRefresh::SaveInventory.save_inventory(@ems, @persister.inventory_collections)

      # Assert saved data
      assert_full_inventory_collections_graph

      # Check that we only updated the existing records
      orchestration_stack_0_1   = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_0_1")
      orchestration_stack_0_2   = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_0_2")
      orchestration_stack_1_11  = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_1_11")
      orchestration_stack_1_12  = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_1_12")
      orchestration_stack_11_21 = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_11_21")
      orchestration_stack_12_22 = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_12_22")
      orchestration_stack_12_23 = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_12_23")

      orchestration_stack_resource_1_11 = OrchestrationStackResource.find_by(
        :ems_ref => "stack_ems_ref_1_11"
      )
      orchestration_stack_resource_1_11_1 = OrchestrationStackResource.find_by(
        :ems_ref => "stack_resource_physical_resource_1_11_1"
      )
      orchestration_stack_resource_1_12 = OrchestrationStackResource.find_by(
        :ems_ref => "stack_ems_ref_1_12"
      )
      orchestration_stack_resource_1_12_1 = OrchestrationStackResource.find_by(
        :ems_ref => "stack_resource_physical_resource_1_12_1"
      )
      orchestration_stack_resource_11_21 = OrchestrationStackResource.find_by(
        :ems_ref => "stack_ems_ref_11_21"
      )
      orchestration_stack_resource_12_22 = OrchestrationStackResource.find_by(
        :ems_ref => "stack_ems_ref_12_22"
      )
      orchestration_stack_resource_12_23 = OrchestrationStackResource.find_by(
        :ems_ref => "stack_ems_ref_12_23"
      )

      expect(orchestration_stack_0_1).to eq(@orchestration_stack_0_1)
      expect(orchestration_stack_0_2).to eq(@orchestration_stack_0_2)
      expect(orchestration_stack_1_11).to eq(@orchestration_stack_1_11)
      expect(orchestration_stack_1_12).to eq(@orchestration_stack_1_12)
      expect(orchestration_stack_11_21).to eq(@orchestration_stack_11_21)
      expect(orchestration_stack_12_22).to eq(@orchestration_stack_12_22)
      expect(orchestration_stack_12_23).to eq(@orchestration_stack_12_23)

      expect(orchestration_stack_resource_1_11).to eq(@orchestration_stack_resource_1_11)
      expect(orchestration_stack_resource_1_11_1).to eq(@orchestration_stack_resource_1_11_1)
      expect(orchestration_stack_resource_1_12).to eq(@orchestration_stack_resource_1_12)
      expect(orchestration_stack_resource_1_12_1).to eq(@orchestration_stack_resource_1_12_1)
      expect(orchestration_stack_resource_11_21).to eq(@orchestration_stack_resource_11_21)
      expect(orchestration_stack_resource_12_22).to eq(@orchestration_stack_resource_12_22)
      expect(orchestration_stack_resource_12_23).to eq(@orchestration_stack_resource_12_23)
    end
  end

  def assert_full_inventory_collections_graph
    # Orchestration stack 0_0 is created as a skeletal record
    orchestration_stack_0_0   = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_0_0")
    orchestration_stack_0_1   = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_0_1")
    orchestration_stack_0_2   = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_0_2")
    orchestration_stack_1_11  = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_1_11")
    orchestration_stack_1_12  = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_1_12")
    orchestration_stack_11_21 = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_11_21")
    orchestration_stack_12_22 = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_12_22")
    orchestration_stack_12_23 = OrchestrationStack.find_by(:ems_ref => "stack_ems_ref_12_23")

    orchestration_stack_resource_1_11 = OrchestrationStackResource.find_by(
      :ems_ref => "stack_ems_ref_1_11"
    )
    orchestration_stack_resource_1_11_1 = OrchestrationStackResource.find_by(
      :ems_ref => "stack_resource_physical_resource_1_11_1"
    )
    orchestration_stack_resource_1_12 = OrchestrationStackResource.find_by(
      :ems_ref => "stack_ems_ref_1_12"
    )
    orchestration_stack_resource_1_12_1 = OrchestrationStackResource.find_by(
      :ems_ref => "stack_resource_physical_resource_1_12_1"
    )
    orchestration_stack_resource_11_21 = OrchestrationStackResource.find_by(
      :ems_ref => "stack_ems_ref_11_21"
    )
    orchestration_stack_resource_12_22 = OrchestrationStackResource.find_by(
      :ems_ref => "stack_ems_ref_12_22"
    )
    orchestration_stack_resource_12_23 = OrchestrationStackResource.find_by(
      :ems_ref => "stack_ems_ref_12_23"
    )

    expect(orchestration_stack_0_1.parent).to eq(orchestration_stack_0_0)
    expect(orchestration_stack_0_2.parent).to eq(orchestration_stack_0_0)
    expect(orchestration_stack_1_11.parent).to eq(orchestration_stack_0_1)
    expect(orchestration_stack_1_12.parent).to eq(orchestration_stack_0_1)
    expect(orchestration_stack_11_21.parent).to eq(orchestration_stack_1_11)
    expect(orchestration_stack_12_22.parent).to eq(orchestration_stack_1_12)
    expect(orchestration_stack_12_23.parent).to eq(orchestration_stack_1_12)

    expect(orchestration_stack_0_1.orchestration_stack_resources).to(
      match_array([orchestration_stack_resource_1_11,
                   orchestration_stack_resource_1_11_1,
                   orchestration_stack_resource_1_12,
                   orchestration_stack_resource_1_12_1])
    )
    expect(orchestration_stack_0_2.orchestration_stack_resources).to(
      match_array(nil)
    )
    expect(orchestration_stack_1_11.orchestration_stack_resources).to(
      match_array([orchestration_stack_resource_11_21])
    )
    expect(orchestration_stack_1_12.orchestration_stack_resources).to(
      match_array([orchestration_stack_resource_12_22, orchestration_stack_resource_12_23])
    )
    expect(orchestration_stack_11_21.orchestration_stack_resources).to(
      match_array(nil)
    )
    expect(orchestration_stack_12_22.orchestration_stack_resources).to(
      match_array(nil)
    )
    expect(orchestration_stack_12_23.orchestration_stack_resources).to(
      match_array(nil)
    )

    expect(orchestration_stack_resource_1_11.stack).to eq(orchestration_stack_0_1)
    expect(orchestration_stack_resource_1_11_1.stack).to eq(orchestration_stack_0_1)
    expect(orchestration_stack_resource_1_12.stack).to eq(orchestration_stack_0_1)
    expect(orchestration_stack_resource_1_12_1.stack).to eq(orchestration_stack_0_1)
    expect(orchestration_stack_resource_11_21.stack).to eq(orchestration_stack_1_11)
    expect(orchestration_stack_resource_12_22.stack).to eq(orchestration_stack_1_12)
    expect(orchestration_stack_resource_12_23.stack).to eq(orchestration_stack_1_12)
  end

  # Initialize the InventoryCollections
  def initialize_inventory_collections(opts = {})
    collections = [
      [:orchestration_stacks, ManageIQ::Providers::CloudManager::OrchestrationStack],
      [:orchestration_stacks_resources, OrchestrationStackResource]
    ]

    (opts[:reversed] ? collections.reverse : collections).each do |params|
      @persister.add_collection(params[0]) do |builder|
        builder.add_properties(
          :model_class => params[1],
        )
      end
    end

    if opts[:add_network_ports]
      @persister.add_collection(:network_ports) do |builder|
        builder.add_properties(
          :model_class => NetworkPort,
          :parent      => @ems.network_manager,
        )
      end
    end
  end

  def init_stack_data_with_stack_stack_cycle
    @persister.orchestration_stacks.build(
      orchestration_stack_data("0_1").merge(
        :parent => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("0_0")[:ems_ref])
      )
    )
    @persister.orchestration_stacks.build(
      orchestration_stack_data("0_2").merge(
        :parent => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("0_0")[:ems_ref])
      )
    )
    @persister.orchestration_stacks.build(
      orchestration_stack_data("1_11").merge(
        :parent => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("0_1")[:ems_ref])
      )
    )
    @persister.orchestration_stacks.build(
      orchestration_stack_data("1_12").merge(
        :parent => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("0_1")[:ems_ref])
      )
    )
    @persister.orchestration_stacks.build(
      orchestration_stack_data("11_21").merge(
        :parent => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("1_11")[:ems_ref])
      )
    )
    @persister.orchestration_stacks.build(
      orchestration_stack_data("12_22").merge(
        :parent => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("1_12")[:ems_ref])
      )
    )
    @persister.orchestration_stacks.build(
      orchestration_stack_data("12_23").merge(
        :parent => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("1_12")[:ems_ref])
      )
    )
  end

  def init_stack_data_with_stack_resource_stack_cycle
    @persister.orchestration_stacks.build(
      orchestration_stack_data("0_1").merge(
        :parent => @persister.orchestration_stacks_resources.lazy_find(orchestration_stack_data("0_1")[:ems_ref],
                                                                       :key => :stack)
      )
    )

    @persister.orchestration_stacks.build(
      orchestration_stack_data("0_2").merge(
        :parent => @persister.orchestration_stacks_resources.lazy_find(orchestration_stack_data("0_2")[:ems_ref],
                                                                       :key => :stack)
      )
    )

    @persister.orchestration_stacks.build(
      orchestration_stack_data("1_11").merge(
        :parent => @persister.orchestration_stacks_resources.lazy_find(orchestration_stack_data("1_11")[:ems_ref],
                                                                       :key => :stack)
      )
    )

    @persister.orchestration_stacks.build(
      orchestration_stack_data("1_12").merge(
        :parent => @persister.orchestration_stacks_resources.lazy_find(orchestration_stack_data("1_12")[:ems_ref],
                                                                       :key => :stack)
      )
    )

    @persister.orchestration_stacks.build(
      orchestration_stack_data("11_21").merge(
        :parent => @persister.orchestration_stacks_resources.lazy_find(orchestration_stack_data("11_21")[:ems_ref],
                                                                       :key => :stack)
      )
    )

    @persister.orchestration_stacks.build(
      orchestration_stack_data("12_22").merge(
        :parent => @persister.orchestration_stacks_resources.lazy_find(orchestration_stack_data("12_22")[:ems_ref],
                                                                       :key => :stack)
      )
    )

    @persister.orchestration_stacks.build(
      orchestration_stack_data("12_23").merge(
        :parent => @persister.orchestration_stacks_resources.lazy_find(orchestration_stack_data("12_23")[:ems_ref],
                                                                       :key => :stack)
      )
    )
  end

  def init_resource_data
    @persister.orchestration_stacks_resources.build(
      orchestration_stack_resource_data("1_11").merge(
        :ems_ref => orchestration_stack_data("1_11")[:ems_ref],
        :stack   => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("0_1")[:ems_ref]),
      )
    )
    @persister.orchestration_stacks_resources.build(
      orchestration_stack_resource_data("1_11_1").merge(
        :stack => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("0_1")[:ems_ref]),
      )
    )
    @persister.orchestration_stacks_resources.build(
      orchestration_stack_resource_data("1_12").merge(
        :ems_ref => orchestration_stack_data("1_12")[:ems_ref],
        :stack   => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("0_1")[:ems_ref]),
      )
    )
    @persister.orchestration_stacks_resources.build(
      orchestration_stack_resource_data("1_12_1").merge(
        :stack => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("0_1")[:ems_ref]),
      )
    )
    @persister.orchestration_stacks_resources.build(
      orchestration_stack_resource_data("11_21").merge(
        :ems_ref => orchestration_stack_data("11_21")[:ems_ref],
        :stack   => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("1_11")[:ems_ref]),
      )
    )
    @persister.orchestration_stacks_resources.build(
      orchestration_stack_resource_data("12_22").merge(
        :ems_ref => orchestration_stack_data("12_22")[:ems_ref],
        :stack   => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("1_12")[:ems_ref]),
      )
    )
    @persister.orchestration_stacks_resources.build(
      orchestration_stack_resource_data("12_23").merge(
        :ems_ref => orchestration_stack_data("12_23")[:ems_ref],
        :stack   => @persister.orchestration_stacks.lazy_find(orchestration_stack_data("1_12")[:ems_ref]),
      )
    )
  end

  def initialize_mocked_records
    @orchestration_stack_0_1 = FactoryBot.create(
      :orchestration_stack_cloud,
      orchestration_stack_data("0_1").merge(
        :ext_management_system => @ems,
        :parent                => nil
      )
    )
    @orchestration_stack_0_2 = FactoryBot.create(
      :orchestration_stack_cloud,
      orchestration_stack_data("0_2").merge(
        :ext_management_system => @ems,
        :parent                => nil
      )
    )
    @orchestration_stack_1_11 = FactoryBot.create(
      :orchestration_stack_cloud,
      orchestration_stack_data("1_11").merge(
        :ext_management_system => @ems,
        :parent                => @orchestration_stack_0_1
      )
    )
    @orchestration_stack_1_12 = FactoryBot.create(
      :orchestration_stack_cloud,
      orchestration_stack_data("1_12").merge(
        :ext_management_system => @ems,
        :parent                => @orchestration_stack_0_1
      )
    )
    @orchestration_stack_11_21 = FactoryBot.create(
      :orchestration_stack_cloud,
      orchestration_stack_data("11_21").merge(
        :ext_management_system => @ems,
        :parent                => @orchestration_stack_1_11
      )
    )
    @orchestration_stack_12_22 = FactoryBot.create(
      :orchestration_stack_cloud,
      orchestration_stack_data("12_22").merge(
        :ext_management_system => @ems,
        :parent                => @orchestration_stack_1_12
      )
    )
    @orchestration_stack_12_23 = FactoryBot.create(
      :orchestration_stack_cloud,
      orchestration_stack_data("12_23").merge(
        :ext_management_system => @ems,
        :parent                => @orchestration_stack_1_12
      )
    )

    @orchestration_stack_resource_1_11 = FactoryBot.create(
      :orchestration_stack_resource,
      orchestration_stack_resource_data("1_11").merge(
        :ems_ref => orchestration_stack_data("1_11")[:ems_ref],
        :stack   => @orchestration_stack_0_1,
      )
    )
    @orchestration_stack_resource_1_11_1 = FactoryBot.create(
      :orchestration_stack_resource,
      orchestration_stack_resource_data("1_11_1").merge(
        :stack => @orchestration_stack_0_1,
      )
    )
    @orchestration_stack_resource_1_12 = FactoryBot.create(
      :orchestration_stack_resource,
      orchestration_stack_resource_data("1_12").merge(
        :ems_ref => orchestration_stack_data("1_12")[:ems_ref],
        :stack   => @orchestration_stack_0_1,
      )
    )
    @orchestration_stack_resource_1_12_1 = FactoryBot.create(
      :orchestration_stack_resource,
      orchestration_stack_resource_data("1_12_1").merge(
        :stack => @orchestration_stack_0_1,
      )
    )
    @orchestration_stack_resource_11_21 = FactoryBot.create(
      :orchestration_stack_resource,
      orchestration_stack_resource_data("11_21").merge(
        :ems_ref => orchestration_stack_data("11_21")[:ems_ref],
        :stack   => @orchestration_stack_1_11,
      )
    )
    @orchestration_stack_resource_12_22 = FactoryBot.create(
      :orchestration_stack_resource,
      orchestration_stack_resource_data("12_22").merge(
        :ems_ref => orchestration_stack_data("12_22")[:ems_ref],
        :stack   => @orchestration_stack_1_12,
      )
    )
    @orchestration_stack_resource_12_23 = FactoryBot.create(
      :orchestration_stack_resource,
      orchestration_stack_resource_data("12_23").merge(
        :ems_ref => orchestration_stack_data("12_23")[:ems_ref],
        :stack   => @orchestration_stack_1_12,
      )
    )
  end
end
