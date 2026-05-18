# frozen_string_literal: true

module WentHiking
  module Import
    class Filter
      def initialize(source_db)
        @source_db = source_db
      end

      def durable_user_ids
        ids = []
        ids.concat(dataset_ids(:trips, :user_id))
        ids.concat(dataset_ids(:comments, :user_id))
        ids.concat(dataset_ids(:hearts, :user_id))
        ids.compact.uniq.sort
      end

      def migrate_user?(legacy_user_id)
        durable_user_ids.include?(legacy_user_id.to_i)
      end

      def avatar_only_user_ids
        return [] unless source_db.table_exists?(:users)
        return [] unless table_column?(:users, :avatar_file_name)

        avatar_ids = source_db[:users]
          .exclude(avatar_file_name: nil)
          .exclude(avatar_file_name: "")
          .select_map(:id)

        (avatar_ids - durable_user_ids).compact.uniq.sort
      end

      private

      attr_reader :source_db

      def dataset_ids(table, column)
        return [] unless source_db.table_exists?(table)

        source_db[table].exclude(column => nil).select_map(column)
      end

      def table_column?(table, column)
        source_db.schema(table).any? { |name, _metadata| name == column }
      end
    end
  end
end
