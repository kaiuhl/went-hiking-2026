# frozen_string_literal: true

require "json"
require "sequel"
require "went_hiking/import/filter"
require "went_hiking/import/transform"
require "went_hiking/models"

module WentHiking
  module Import
    class Runner
      REPORT_SAMPLE_LIMIT = 100

      def initialize(source_db:, target_db: WentHiking.db)
        @source_db = source_db
        @target_db = target_db
        @filter = Filter.new(source_db)
        @transform = Transform.new
        @summary = {
          orphan_references: Hash.new(0),
          skipped_rows: []
        }
        @upsert_cache = {}
        @accounts_by_legacy_id = {}
        @trips_by_legacy_id = {}
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
          record_avatar_only_users
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
          values = transform.account(symbolize(row))
          account_id = upsert(:accounts, :legacy_user_id, values)
          @accounts_by_legacy_id[values.fetch(:legacy_user_id)] = values.merge(id: account_id)
          increment(:accounts)
        end
      end

      def import_trips
        source_db[:trips].each do |row|
          row = symbolize(row)
          account = account_for(row[:user_id])
          unless account
            record_skip(:trips, row, :missing_account, legacy_user_id: row[:user_id])
            next
          end

          values = transform.trip(row, account_id: account[:id])
          trip_id = upsert(:trips, :legacy_trip_id, values)
          @trips_by_legacy_id[values.fetch(:legacy_trip_id)] = values.merge(id: trip_id)
          increment(:trips)
        end
      end

      def import_photos
        source_db[:photos].each do |row|
          row = symbolize(row)
          trip = trip_for(row[:trip_id])
          account = account_for(row[:user_id]) || account_for_trip(trip)
          unless trip && account
            reason = trip ? :missing_account : :missing_trip
            record_skip(:photos, row, reason, legacy_user_id: row[:user_id], legacy_trip_id: row[:trip_id])
            next
          end

          photo_id = upsert(:photos, :legacy_photo_id, transform.photo(row, account_id: account[:id], trip_id: trip[:id]))
          transform.photo_variants(row).each do |variant|
            variant[:photo_id] = photo_id
            upsert_variant(variant)
          end
          increment(:photos)
        end
      end

      def import_comments
        return unless source_db.table_exists?(:comments)

        source_db[:comments].each do |row|
          row = symbolize(row)
          account = account_for(row[:user_id])
          trip = trip_for(row[:trip_id])
          unless account && trip
            reason = account ? :missing_trip : :missing_account
            record_skip(:comments, row, reason, legacy_user_id: row[:user_id], legacy_trip_id: row[:trip_id])
            next
          end

          upsert(:comments, :legacy_comment_id, transform.comment(row, account_id: account[:id], trip_id: trip[:id]))
          increment(:comments)
        end
      end

      def import_hearts
        return unless source_db.table_exists?(:hearts)

        source_db[:hearts].each do |row|
          row = symbolize(row)
          account = account_for(row[:user_id])
          trip = trip_for(row[:trip_id])
          unless account && trip
            reason = account ? :missing_trip : :missing_account
            record_skip(:hearts, row, reason, legacy_user_id: row[:user_id], legacy_trip_id: row[:trip_id])
            next
          end

          upsert(:hearts, :legacy_heart_id, transform.heart(row, account_id: account[:id], trip_id: trip[:id]))
          increment(:hearts)
        end
      end

      def record_avatar_only_users
        ids = filter.avatar_only_user_ids
        summary[:avatar_only_user_count] = ids.size
        summary[:avatar_only_user_ids_sample] = ids.first(REPORT_SAMPLE_LIMIT)
      end

      def increment(key)
        summary[key] ||= 0
        summary[key] += 1
      end

      def record_skip(table, row, reason, references)
        increment(:"skipped_#{table}")
        summary[:orphan_references][reason] += 1

        if summary[:skipped_rows].size < REPORT_SAMPLE_LIMIT
          summary[:skipped_rows] << {
            table: table,
            legacy_id: row[:id],
            reason: reason,
            references: references
          }
        else
          increment(:skipped_rows_truncated)
        end
      end

      def upsert(table, key, values)
        dataset = target_db[table]
        cache = upsert_cache(table, key)
        cache_key = values.fetch(key)
        if (existing_id = cache[cache_key])
          dataset.where(id: existing_id).update(values.merge(updated_at: Time.now))
          existing_id
        else
          dataset.insert(values).tap do |id|
            cache[cache_key] = id
          end
        end
      end

      def upsert_variant(values)
        dataset = target_db[:photo_variants]
        cache = variant_cache
        cache_key = [values.fetch(:photo_id), values.fetch(:style)]
        if (existing_id = cache[cache_key])
          dataset.where(id: existing_id).update(values.merge(updated_at: Time.now))
          existing_id
        else
          dataset.insert(values).tap do |id|
            cache[cache_key] = id
          end
        end
      end

      def account_for(legacy_user_id)
        return nil if legacy_user_id.nil?

        @accounts_by_legacy_id[legacy_user_id] ||= target_db[:accounts].where(legacy_user_id: legacy_user_id).first
      end

      def account_for_trip(trip)
        return nil unless trip

        target_db[:accounts].where(id: trip[:account_id]).first
      end

      def trip_for(legacy_trip_id)
        @trips_by_legacy_id[legacy_trip_id] ||= target_db[:trips].where(legacy_trip_id: legacy_trip_id).first
      end

      def symbolize(row)
        row.to_h.transform_keys(&:to_sym)
      end

      def upsert_cache(table, key)
        @upsert_cache[[table, key]] ||= target_db[table]
          .select(key, :id)
          .all
          .each_with_object({}) { |row, cache| cache[row[key]] = row[:id] }
      end

      def variant_cache
        @variant_cache ||= target_db[:photo_variants]
          .select(:photo_id, :style, :id)
          .all
          .each_with_object({}) { |row, cache| cache[[row[:photo_id], row[:style]]] = row[:id] }
      end
    end
  end
end
