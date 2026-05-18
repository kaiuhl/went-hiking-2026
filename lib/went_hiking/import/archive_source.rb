# frozen_string_literal: true

require "json"
require "time"

module WentHiking
  module Import
    class ArchiveSource
      TIMESTAMP_COLUMNS = %i[
        created_at
        updated_at
        hiked_at
        taken_at
        last_request_at
        legacy_last_request_at
      ].freeze

      def initialize(path)
        @path = Pathname(path)
        @rows = {}
      end

      def uri
        "legacy-archive://#{path}"
      end

      def table_exists?(table)
        file_for(table).file?
      end

      def [](table)
        Dataset.new(rows_for(table))
      end

      def schema(table)
        rows_for(table).first&.keys&.map { |key| [key, {}] } || []
      end

      private

      attr_reader :path

      def rows_for(table)
        key = table.to_sym
        @rows[key] ||= load_rows(key)
      end

      def load_rows(table)
        file = file_for(table)
        return [] unless file.file?

        file.each_line(chomp: true).filter_map do |line|
          next if line.empty?

          row = JSON.parse(line, symbolize_names: true)
          row.each_with_object({}) do |(column, value), normalized|
            normalized[column] = normalize_value(column, value)
          end
        end
      end

      def file_for(table)
        path.join("#{table}.jsonl")
      end

      def normalize_value(column, value)
        return nil if value.nil?
        return value unless TIMESTAMP_COLUMNS.include?(column.to_sym)

        Time.parse(value.to_s)
      rescue ArgumentError
        value
      end

      class Dataset
        include Enumerable

        def initialize(rows)
          @rows = rows
        end

        def each(&block)
          rows.each(&block)
        end

        def where(conditions)
          self.class.new(filter_rows(conditions, include_matches: true))
        end

        def exclude(conditions)
          self.class.new(filter_rows(conditions, include_matches: false))
        end

        def select_map(column)
          rows.map { |row| row[column.to_sym] }
        end

        private

        attr_reader :rows

        def filter_rows(conditions, include_matches:)
          rows.select do |row|
            matched = conditions.all? do |key, expected|
              value = row[key.to_sym]
              expected.is_a?(Array) ? expected.include?(value) : value == expected
            end
            include_matches ? matched : !matched
          end
        end
      end
    end
  end
end
