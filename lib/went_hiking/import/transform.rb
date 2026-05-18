# frozen_string_literal: true

require "time"
require "went_hiking/s3_keys"
require "went_hiking/slug"

module WentHiking
  module Import
    class Transform
      PHOTO_STYLES = %w[original micro thumbnail bpl large medium].freeze
      AVATAR_STYLES = %w[original micro thumbnail medium].freeze

      def account(row)
        {
          legacy_user_id: row[:id],
          email: row[:email].to_s.strip.downcase,
          name: present(row[:name]) || row[:email].to_s.split("@").first,
          slug: Slug.generate(present(row[:name]) || row[:email]),
          status_id: 1,
          location: present(row[:location]),
          admin: truthy?(row[:admin]),
          avatar_file_name: present(row[:avatar_file_name]),
          avatar_content_type: present(row[:avatar_content_type]),
          avatar_file_size: row[:avatar_file_size],
          legacy_last_request_at: row[:last_request_at],
          created_at: row[:created_at] || Time.now,
          updated_at: row[:updated_at] || Time.now
        }
      end

      def trip(row, account_id:)
        {
          legacy_trip_id: row[:id],
          account_id: account_id,
          name: row[:name].to_s,
          slug: Slug.generate(row[:name]),
          source_url: present(row[:url]),
          nights: row[:nights].to_i,
          mileage: row[:mileage],
          elevation: row[:elevation],
          hiked_at: row[:hiked_at],
          lat: row[:lat],
          lng: row[:lng],
          report_markdown: present(row[:report]),
          created_at: row[:created_at] || Time.now,
          updated_at: row[:updated_at] || Time.now
        }
      end

      def photo(row, account_id:, trip_id:)
        {
          legacy_photo_id: row[:id],
          account_id: account_id,
          trip_id: trip_id,
          legacy_image_file_name: present(row[:image_file_name]),
          content_type: present(row[:image_content_type]),
          file_size: row[:image_file_size],
          width: row[:width],
          height: row[:height],
          taken_at: row[:taken_at],
          lat: row[:lat],
          lng: row[:lng],
          caption: present(row[:caption]),
          camera_model: present(row[:camera_model]),
          camera_exposure: present(row[:camera_exposure]),
          camera_f_stop: row[:camera_f_stop],
          camera_iso: row[:camera_iso],
          legacy_stats_added: truthy?(row[:stats_added]),
          created_at: row[:created_at] || Time.now,
          updated_at: row[:updated_at] || Time.now
        }
      end

      def photo_variants(row)
        filename = row[:image_file_name].to_s
        return [] if filename.empty?

        PHOTO_STYLES.map do |style|
          path = S3Keys.photo_variant_key(photo_id: row[:id], style: style, filename: derivative_filename(filename, style))
          {
            style: style,
            filename: File.basename(path),
            legacy_path: path,
            s3_key: path,
            created_at: row[:created_at] || Time.now,
            updated_at: row[:updated_at] || Time.now
          }
        end
      end

      def comment(row, account_id:, trip_id:)
        {
          legacy_comment_id: row[:id],
          account_id: account_id,
          trip_id: trip_id,
          body_markdown: row[:body].to_s,
          legacy_read_only: true,
          created_at: row[:created_at] || Time.now,
          updated_at: row[:updated_at] || Time.now
        }
      end

      def heart(row, account_id:, trip_id:)
        {
          legacy_heart_id: row[:id],
          account_id: account_id,
          trip_id: trip_id,
          legacy_read_only: true,
          created_at: row[:created_at] || Time.now,
          updated_at: row[:updated_at] || Time.now
        }
      end

      private

      def present(value)
        stripped = value.to_s.strip
        stripped.empty? ? nil : stripped
      end

      def truthy?(value)
        value == true || value.to_s == "1"
      end

      def derivative_filename(filename, style)
        return filename if style == "original"

        base = File.basename(filename, ".*")
        "#{base}.jpg"
      end
    end
  end
end
