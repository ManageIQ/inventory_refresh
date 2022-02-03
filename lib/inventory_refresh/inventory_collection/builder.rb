module InventoryRefresh
  class InventoryCollection
    class Builder
      class MissingModelClassError < StandardError; end

      def self.allowed_properties
        %i(all_manager_uuids            arel                    association
           attributes_blacklist         attributes_whitelist    batch_extra_attributes
           complete                     create_only             custom_save_block
           custom_reconnect_block       default_values          delete_method
           dependency_attributes        check_changed           inventory_object_attributes
           manager_ref                  manager_ref_allowed_nil
           model_class                  name                    parent
           parent_inventory_collections retention_strategy      strategy
           saver_strategy               secondary_refs          targeted
           targeted_arel                update_only             use_ar_object
           assert_graph_integrity).to_set
      end

      def allowed_properties
        @allowed_properties ||= self.class.allowed_properties
      end

      # Default options for builder
      #   :adv_settings
      #     - values from Advanced settings (doesn't overwrite values specified in code)
      #     - @see method ManageIQ::Providers::Inventory::Persister.make_builder_settings()
      #   :shared_properties
      #     - any properties applied if missing (not explicitly specified)
      def self.default_options
        {
          :shared_properties => {},
        }
      end

      # Entry point
      # Creates builder and builds data for inventory collection
      # @param name [Symbol, Array] InventoryCollection.association value. <name> method not called when Array
      #        (optional) method with this name also used for concrete inventory collection specific properties
      # @param persister_class [Class] used for "guessing" model_class
      # @param options [Hash]
      def self.prepare_data(name, persister_class, options = {})
        options = default_options.merge(options)
        builder = new(name, persister_class, options)
        builder.construct_data

        yield(builder) if block_given?

        builder
      end

      # @see prepare_data()
      def initialize(name, persister_class, options = self.class.default_options)
        @name = name
        @persister_class = persister_class

        @properties = {}
        @inventory_object_attributes = []
        @default_values = {}
        @dependency_attributes = {}

        @options = options
        skip_auto_inventory_attributes(false) if @options[:auto_inventory_attributes].nil?
        skip_model_class(false) if @options[:without_model_class].nil?

        @shared_properties = options[:shared_properties] # From persister
      end

      # Builds data for InventoryCollection
      # Calls method @name (if exists) with specific properties
      # Yields for overwriting provider-specific properties
      def construct_data
        add_properties({:association => @name}, :if_missing)

        add_properties(@shared_properties, :if_missing)

        send(@name.to_sym) if @name.respond_to?(:to_sym) && respond_to?(@name.to_sym)

        if @properties[:model_class].nil?
          add_properties(:model_class => auto_model_class) unless @options[:without_model_class]
        end
      end

      # Creates InventoryCollection
      def to_inventory_collection
        if @properties[:model_class].nil? && !@options[:without_model_class]
          raise MissingModelClassError, "Missing model_class for :#{@name} (\"#{@name.to_s.classify}\" or subclass expected)."
        end

        ::InventoryRefresh::InventoryCollection.new(to_hash)
      end

      #
      # Missing method
      #   - add_some_property(value)
      # converted to:
      #   - add_properties(:some_property => value)
      #
      def method_missing(method_name, *arguments, &block)
        if method_name.to_s.starts_with?('add_')
          add_properties(
            method_name.to_s.gsub('add_', '').to_sym => arguments[0]
          )
        else
          super
        end
      end

      def respond_to_missing?(method_name, _include_private = false)
        method_name.to_s.starts_with?('add_')
      end

      # Merges @properties
      # @see ManagerRefresh::InventoryCollection.initialize for list of properties
      #
      # @param props [Hash]
      # @param mode [Symbol] :overwrite | :if_missing
      def add_properties(props = {}, mode = :overwrite)
        props.each_key { |property_name| assert_allowed_property(property_name) }

        @properties = merge_hashes(@properties, props, mode)
      end

      # Adds inventory object attributes (part of @properties)
      def add_inventory_attributes(array)
        @inventory_object_attributes += (array || [])
      end

      # Removes specified inventory object attributes
      def remove_inventory_attributes(array)
        @inventory_object_attributes -= (array || [])
      end

      # Clears all inventory object attributes
      def clear_inventory_attributes!
        @options[:auto_inventory_attributes] = false
        @inventory_object_attributes = []
      end

      # Adds key/values to default values (InventoryCollection.default_values) (part of @properties)
      def add_default_values(params = {}, mode = :overwrite)
        @default_values = merge_hashes(@default_values, params, mode)
      end

      # Evaluates lambda blocks
      def evaluate_lambdas!(persister)
        @default_values = evaluate_lambdas_on(@default_values, persister)
        @dependency_attributes = evaluate_lambdas_on(@dependency_attributes, persister)
      end

      # Adds key/values to dependency_attributes (part of @properties)
      def add_dependency_attributes(attrs = {}, mode = :overwrite)
        @dependency_attributes = merge_hashes(@dependency_attributes, attrs, mode)
      end

      # Deletes key from dependency_attributes
      def remove_dependency_attributes(key)
        @dependency_attributes.delete(key)
      end

      # Returns whole InventoryCollection properties
      def to_hash
        add_inventory_attributes(auto_inventory_attributes) if @options[:auto_inventory_attributes]

        @properties[:inventory_object_attributes] ||= @inventory_object_attributes

        @properties[:default_values] ||= {}
        @properties[:default_values].merge!(@default_values)

        @properties[:dependency_attributes] ||= {}
        @properties[:dependency_attributes].merge!(@dependency_attributes)

        @properties
      end

      protected

      def assert_allowed_property(name)
        unless allowed_properties.include?(name)
          raise "InventoryCollection property :#{name} is not allowed. Allowed properties are:\n#{self.allowed_properties.to_a.map(&:to_s).join(', ')}"
        end
      end

      # Extends source hash with
      # - a) all keys from dest (overwrite mode)
      # - b) missing keys (missing mode)
      #
      # @param mode [Symbol] :overwrite | :if_missing
      def merge_hashes(source, dest, mode)
        return source if source.nil? || dest.nil?

        if mode == :overwrite
          source.merge(dest)
        else
          dest.merge(source)
        end
      end

      # Derives model_class from @name
      # Can be disabled by options :without_model_class => true
      # @return [Class | nil] when class doesn't exist, returns nil
      def auto_model_class
        "::#{@name.to_s.classify}".safe_constantize
      end

      # Enables/disables auto_model_class and exception check
      # @param skip [Boolean]
      def skip_model_class(skip = true)
        @options[:without_model_class] = skip
      end

      # Inventory object attributes are derived from setters
      #
      # Can be disabled by options :auto_inventory_attributes => false
      #   - attributes can be manually set via method add_inventory_attributes()
      def auto_inventory_attributes
        return if @properties[:model_class].nil?

        (@properties[:model_class].new.methods - ar_base_class.methods).grep(/^[\w]+?\=$/).collect do |setter|
          setter.to_s[0..setter.length - 2].to_sym
        end
      end

      # used for ignoring unrelated auto_inventory_attributes
      def ar_base_class
        ActiveRecord::Base
      end

      # Enables/disables auto_inventory_attributes
      # @param skip [Boolean]
      def skip_auto_inventory_attributes(skip = true)
        @options[:auto_inventory_attributes] = !skip
      end

      # Evaluates lambda blocks in @default_values and @dependency_attributes
      # @param values [Hash]
      # @param persister [ManageIQ::Providers::Inventory::Persister]
      def evaluate_lambdas_on(values, persister)
        values&.transform_values do |value|
          if value.respond_to?(:call)
            value.call(persister)
          else
            value
          end
        end
      end
    end
  end
end
