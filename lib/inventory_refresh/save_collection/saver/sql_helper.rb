require "inventory_refresh/save_collection/saver/sql_helper_update"
require "inventory_refresh/save_collection/saver/sql_helper_upsert"
require "inventory_refresh/logging"
require "active_support/concern"

module InventoryRefresh::SaveCollection
  module Saver
    module SqlHelper
      include InventoryRefresh::Logging

      # TODO(lsmola) all below methods should be rewritten to arel, but we need to first extend arel to be able to do
      # this

      extend ActiveSupport::Concern

      included do
        include SqlHelperUpsert
        include SqlHelperUpdate
      end

      # Returns quoted column name
      # @param key [Symbol] key that is column name
      # @returns [String] quoted column name
      def quote_column_name(key)
        get_connection.quote_column_name(key)
      end

      # @return [ActiveRecord::ConnectionAdapters::AbstractAdapter] ActiveRecord connection
      def get_connection
        ActiveRecord::Base.connection
      end

      # Builds a multiselection conditions like (table1.a = a1 AND table2.b = b1) OR (table1.a = a2 AND table2.b = b2)
      #
      # @param hashes [Array<Hash>] data we want to use for the query
      # @return [String] condition usable in .where of an ActiveRecord relation
      def build_multi_selection_query(hashes)
        inventory_collection.build_multi_selection_condition(hashes, unique_index_columns)
      end

      # Quotes a value. For update query, the value also needs to be explicitly casted, which we can do by
      # type_cast_for_pg param set to true.
      #
      # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter] ActiveRecord connection
      # @param value [Object] value we want to quote
      # @param name [Symbol] name of the column
      # @param type_cast_for_pg [Boolean] true if we want to also cast the quoted value
      # @return [String] quoted and based on type_cast_for_pg param also casted value
      def quote(connection, value, name = nil, type_cast_for_pg = nil)
        # TODO(lsmola) needed only because UPDATE FROM VALUES needs a specific PG typecasting, remove when fixed in PG
        if type_cast_for_pg
          quote_and_pg_type_cast(connection, value, name)
        else
          connection.quote(value)
        end
      rescue TypeError => e
        logger.error("Can't quote value: #{value}, of :#{name} and #{inventory_collection}")
        raise e
      end

      # Quotes and type casts the value.
      #
      # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter] ActiveRecord connection
      # @param value [Object] value we want to quote
      # @param name [Symbol] name of the column
      # @return [String] quoted and casted value
      def quote_and_pg_type_cast(connection, value, name)
        pg_type_cast(
          connection.quote(value),
          pg_types[name]
        )
      end

      # Returns a type casted value in format needed by PostgreSQL
      #
      # @param value [Object] value we want to quote
      # @param sql_type [String] PostgreSQL column type
      # @return [String] type casted value in format needed by PostgreSQL
      def pg_type_cast(value, sql_type)
        if sql_type.nil?
          value
        else
          "#{value}::#{sql_type}"
        end
      end

      # Effective way of doing multiselect
      #
      # If we use "(col1, col2) IN [(a,e), (b,f), (b,e)]" it's not great, just with 10k batch, we see
      # *** ActiveRecord::StatementInvalid Exception: PG::StatementTooComplex: ERROR:  stack depth limit exceeded
      # HINT:  Increase the configuration parameter "max_stack_depth" (currently 2048kB), after ensuring the
      # platform's stack depth limit is adequate.
      #
      # If we use "(col1 = a AND col2 = e) OR (col1 = b AND col2 = f) OR (col1 = b AND col2 = e)" with 10k batch, it
      # takes about 6s and consumes 300MB, with 100k it takes ~1h and consume 3GB in Postgre process
      #
      # The best way seems to be using CTE, where the list of values we want to map is turned to 'table' and we just
      # do RIGHT OUTER JOIN to get the complement of given identifiers. Tested on getting complement of 100k items,
      # using 2 cols (:ems_ref and :uid_ems) from total 150k rows. It takes ~1s and 350MB in Postgre process
      #
      # @param manager_uuids [Array<String>, Array[Hash]] Array with manager_uuids of entities. The keys have to match
      #        inventory_collection.manager_ref. We allow passing just array of strings, if manager_ref.size ==1, to
      #        spare some memory
      # @return [Arel::SelectManager] Arel for getting complement of uuids. This method modifies the passed
      #         manager_uuids to spare some memory
      def complement_of!(manager_uuids, all_manager_uuids_scope, all_manager_uuids_timestamp)
        all_attribute_keys       = inventory_collection.manager_ref
        all_attribute_keys_array = inventory_collection.manager_ref.map(&:to_s)

        active_entities     = Arel::Table.new(:active_entities)
        active_entities_cte = Arel::Nodes::As.new(
          active_entities,
          Arel.sql("(#{active_entities_query(all_attribute_keys_array, manager_uuids)})")
        )

        all_entities     = Arel::Table.new(:all_entities)
        all_entities_cte = Arel::Nodes::As.new(
          all_entities,
          Arel.sql("(#{all_entities_query(all_manager_uuids_scope, all_manager_uuids_timestamp).select(:id, *all_attribute_keys_array).to_sql})")
        )
        join_condition   = all_attribute_keys.map { |key| active_entities[key].eq(all_entities[key]) }.inject(:and)
        where_condition  = all_attribute_keys.map { |key| active_entities[key].eq(nil) }.inject(:and)

        active_entities
          .project(all_entities[:id])
          .join(all_entities, Arel::Nodes::RightOuterJoin)
          .on(join_condition)
          .with(active_entities_cte, all_entities_cte)
          .where(where_condition)
      end

      private

      def all_entities_query(all_manager_uuids_scope, all_manager_uuids_timestamp)
        all_entities_query = inventory_collection.full_collection_for_comparison
        all_entities_query = all_entities_query.active if inventory_collection.retention_strategy == :archive

        if all_manager_uuids_scope
          scope_keys = all_manager_uuids_scope.first.keys.map { |x| association_to_foreign_key_mapping[x.to_sym] }.map(&:to_s)
          scope = load_scope(all_manager_uuids_scope)
          condition = inventory_collection.build_multi_selection_condition(scope, scope_keys)
          all_entities_query = all_entities_query.where(condition)
        end

        if all_manager_uuids_timestamp && supports_column?(:resource_timestamp)
          all_manager_uuids_timestamp = Time.parse(all_manager_uuids_timestamp)

          date_field = model_class.arel_table[:resource_timestamp]
          all_entities_query = all_entities_query.where(date_field.lt(all_manager_uuids_timestamp))
        end
        all_entities_query
      end

      def load_scope(all_manager_uuids_scope)
        scope_keys = all_manager_uuids_scope.first.keys.to_set

        all_manager_uuids_scope.map do |cond|
          assert_scope!(scope_keys, cond)

          cond.map do |key, value|
            foreign_key       = association_to_foreign_key_mapping[key.to_sym]
            foreign_key_value = value.load&.id

            assert_foreign_keys!(key, value, foreign_key, foreign_key_value)

            [foreign_key, foreign_key_value]
          end.to_h
        end
      end

      def assert_scope!(scope_keys, cond)
        if cond.keys.to_set != scope_keys
          raise "'#{inventory_collection}' expected keys for :all_manager_uuids_scope are #{scope_keys.to_a}, got"\
                " #{cond.keys}. Keys must be the same for all scopes provided."
        end
      end

      def assert_foreign_keys!(key, value, foreign_key, foreign_key_value)
        unless foreign_key
          raise "'#{inventory_collection}' doesn't have relation :#{key} provided in :all_manager_uuids_scope."
        end

        unless foreign_key_value
          raise "'#{inventory_collection}' couldn't load scope value :#{key} => #{value.inspect} provided in :all_manager_uuids_scope"
        end
      end

      def active_entities_query(all_attribute_keys_array, manager_uuids)
        connection = ActiveRecord::Base.connection

        all_attribute_keys_array_q = all_attribute_keys_array.map { |x| quote_column_name(x) }
        # For Postgre, only first set of values should contain the type casts
        first_value = manager_uuids.shift.to_h
        first_value = "(#{all_attribute_keys_array.map { |x| quote(connection, first_value[x], x, true) }.join(",")})"

        # Rest of the values, without the type cast
        values = manager_uuids.map! do |hash|
          "(#{all_attribute_keys_array.map { |x| quote(connection, hash[x], x, false) }.join(",")})"
        end.join(",")

        values = values.blank? ? first_value : [first_value, values].join(",")

        <<-SQL
          SELECT *
          FROM   (VALUES #{values}) AS active_entities_table(#{all_attribute_keys_array_q.join(",")})
        SQL
      end
    end
  end
end
