# frozen_string_literal: true

require "json"
require "sequel"
require "went_hiking/import/filter"
require "went_hiking/import/transform"
require "went_hiking/models"

module WentHiking
  module Import
    class Runner
      def initialize(source_db:, target_db: WentHiking.db)
        @source_db = source_db
        @target_db = target_db
        @filter = Filter.new(source_db)
        @transform = Transform.new
        @summary = Hash.new(0)
      end

      def run
        import_run = Models::ImportRun.create(
          source: source_label,
          status: "running",
          started_at: Time.now,
          created_at: Time.now,
          updated_at: Time.now
        )

        target_db.transaction do
          import_accounts
          import_trips
          import_photos
          import_comments
          import_hearts
        end

        import_run.update(status: "finished", finished_at: Time.now, summary_json: JSON.pretty_generate(summary))
        summary
      rescue => error
        import_run&.update(status: "failed", finished_at: Time.now, summary_json: JSON.pretty_generate(summary.merge(error: error.message)))
        raise
      end

      attr_reader :summary

      private

      attr_reader :source_db, :target_db, :filter, :transform

      def source_label
        source_db.uri || "legacy"
      rescue NoMethodError
        "legacy"
      end

      def import_accounts
        durable_ids = filter.durable_user_ids
        source_db[:users].where(id: durable_ids).each do |row|
          upsert(:accounts, :legacy_user_id, transform.account(symbolize(row)))
          summary[:accounts] += 1
        end
      end

      def import_trips
        source_db[:trips].each do |row|
          row = symbolize(row)
          account = account_for(row[:user_id])
          unless account
            summary[:skipped_trips] += 1
            next
          end

          upsert(:trips, :legacy_trip_id, transform.trip(row, account_id: account[:id]))
          summary[:trips] += 1
        end
      end

      def import_photos
        source_db[:photos].each do |row|
          row = symbolize(row)
          account = account_for(row[:user_id])
          trip = trip_for(row[:trip_id])
          unless account && trip
            summary[:skipped_photos] += 1
            next
          end

          photo_id = upsert(:photos, :legacy_photo_id, transform.photo(row, account_id: account[:id], trip_id: trip[:id]))
          transform.photo_variants(row).each do |variant|
            variant[:photo_id] = photo_id
            upsert_variant(variant)
          end
          summary[:photos] += 1
        end
      end

      def import_comments
        return unless source_db.table_exists?(:comments)

        source_db[:comments].each do |row|
          row = symbolize(row)
          account = account_for(row[:user_id])
          trip = trip_for(row[:trip_id])
          unless account && trip
            summary[:skipped_comments] += 1
            next
          end

          upsert(:comments, :legacy_comment_id, transform.comment(row, account_id: account[:id], trip_id: trip[:id]))
          summary[:comments] += 1
        end
      end

      def import_hearts
        return unless source_db.table_exists?(:hearts)

        source_db[:hearts].each do |row|
          row = symbolize(row)
          account = account_for(row[:user_id])
          trip = trip_for(row[:trip_id])
          unless account && trip
            summary[:skipped_hearts] += 1
            next
          end

          upsert(:hearts, :legacy_heart_id, transform.heart(row, account_id: account[:id], trip_id: trip[:id]))
          summary[:hearts] += 1
        end
      end

      def upsert(table, key, values)
        dataset = target_db[table]
        existing = dataset.where(key => values.fetch(key)).first
        if existing
          dataset.where(id: existing[:id]).update(values.merge(updated_at: Time.now))
          existing[:id]
        else
          dataset.insert(values)
        end
      end

      def upsert_variant(values)
        dataset = target_db[:photo_variants]
        existing = dataset.where(photo_id: values.fetch(:photo_id), style: values.fetch(:style)).first
        if existing
          dataset.where(id: existing[:id]).update(values.merge(updated_at: Time.now))
          existing[:id]
        else
          dataset.insert(values)
        end
      end

      def account_for(legacy_user_id)
        target_db[:accounts].where(legacy_user_id: legacy_user_id).first
      end

      def trip_for(legacy_trip_id)
        target_db[:trips].where(legacy_trip_id: legacy_trip_id).first
      end

      def symbolize(row)
        row.to_h.transform_keys(&:to_sym)
      end
    end
  end
end
