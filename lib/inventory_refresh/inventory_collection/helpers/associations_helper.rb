require_relative "../helpers"

module InventoryRefresh
  class InventoryCollection
    module Helpers
      module AssociationsHelper
        # @return [Array<ActiveRecord::Reflection::BelongsToReflection">] All belongs_to associations
        def belongs_to_associations
          model_class.reflect_on_all_associations.select { |x| x.kind_of?(ActiveRecord::Reflection::BelongsToReflection) }
        end

        # @return [Hash{Symbol => String}] Hash with association name mapped to foreign key column name
        def association_to_foreign_key_mapping
          return {} unless model_class

          @association_to_foreign_key_mapping ||= belongs_to_associations.each_with_object({}) do |x, obj|
            obj[x.name] = x.foreign_key
          end
        end

        # @return [Hash{String => Hash}] Hash with foreign_key column name mapped to association name
        def foreign_key_to_association_mapping
          return {} unless model_class

          @foreign_key_to_association_mapping ||= belongs_to_associations.each_with_object({}) do |x, obj|
            obj[x.foreign_key] = x.name
          end
        end

        # @return [Hash{Symbol => String}] Hash with association name mapped to polymorphic foreign key type column name
        def association_to_foreign_type_mapping
          return {} unless model_class

          @association_to_foreign_type_mapping ||= model_class.reflect_on_all_associations.each_with_object({}) do |x, obj|
            obj[x.name] = x.foreign_type if x.polymorphic?
          end
        end

        # @return [Hash{Symbol => String}] Hash with polymorphic foreign key type column name mapped to association name
        def foreign_type_to_association_mapping
          return {} unless model_class

          @foreign_type_to_association_mapping ||= model_class.reflect_on_all_associations.each_with_object({}) do |x, obj|
            obj[x.foreign_type] = x.name if x.polymorphic?
          end
        end

        # @return [Hash{Symbol => String}] Hash with association name mapped to base class of the association
        def association_to_base_class_mapping
          return {} unless model_class

          @association_to_base_class_mapping ||= model_class.reflect_on_all_associations.each_with_object({}) do |x, obj|
            obj[x.name] = x.klass.base_class.name unless x.polymorphic?
          end
        end

        # @return [Array<Symbol>] List of all column names that are foreign keys
        def foreign_keys
          return [] unless model_class

          @foreign_keys_cache ||= belongs_to_associations.map(&:foreign_key).map!(&:to_sym)
        end

        # @return [Array<Symbol>] List of all column names that are foreign keys and cannot removed, otherwise we couldn't
        #         save the record
        def fixed_foreign_keys
          # Foreign keys that are part of a manager_ref must be present, otherwise the record would get lost. This is a
          # minimum check we can do to not break a referential integrity.
          return @fixed_foreign_keys_cache unless @fixed_foreign_keys_cache.nil?

          manager_ref_set = (manager_ref - manager_ref_allowed_nil)
          @fixed_foreign_keys_cache = manager_ref_set.map { |x| association_to_foreign_key_mapping[x] }.compact
          @fixed_foreign_keys_cache += foreign_keys & manager_ref
          @fixed_foreign_keys_cache.map!(&:to_sym)
          @fixed_foreign_keys_cache
        end
      end
    end
  end
end
