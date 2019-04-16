require "active_support/core_ext/module/delegation"

module InventoryRefresh
  class InventoryCollection
    module Index
      module Type
        class Base
          # @param inventory_collection [InventoryRefresh::InventoryCollection] InventoryCollection owning the index
          # @param index_name
          def initialize(inventory_collection, index_name, attribute_names, *_args)
            @index = {}

            @inventory_collection = inventory_collection
            @index_name           = index_name
            @attribute_names      = attribute_names

            assert_attribute_names!
          end

          delegate :keys, :to => :index

          # Indexes passed InventoryObject
          #
          # @param inventory_object [InventoryRefresh::InventoryObject] InventoryObject we want to index
          # @return [InventoryRefresh::InventoryObject] InventoryObject object
          def store_index_for(inventory_object)
            index[build_stringified_reference(inventory_object.data, attribute_names)] = inventory_object
          end

          # @return [Array] Returns index data
          def index_data
            index.values
          end

          # Find value based on index_value
          #
          # @param _index_value [String] a index_value of the InventoryObject we search for
          def find(_index_value)
            raise "Implement in subclass"
          end

          protected

          attr_reader :attribute_names, :index, :index_name, :inventory_collection

          private

          attr_writer :index

          delegate :build_stringified_reference, :data, :model_class, :custom_save_block, :to => :inventory_collection

          # Asserts that InventoryCollection model has attributes specified for index
          def assert_attribute_names!
            # Skip for manually defined nodes
            return if model_class.nil?
            # When we do custom saving, we allow any indexes to be passed, to no limit the user
            return unless custom_save_block.nil?

            # We cannot simply do model_class.method_defined?(attribute_name.to_sym), because e.g. db attributes seems
            # to be create lazily
            test_model_object = model_class.new
            attribute_names.each do |attribute_name|
              unless test_model_object.respond_to?(attribute_name.to_sym)
                raise "Invalid definition of index :#{index_name}, there is no attribute :#{attribute_name} on model #{model_class}"
              end
            end
          end
        end
      end
    end
  end
end
