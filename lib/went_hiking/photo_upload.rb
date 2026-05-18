# frozen_string_literal: true

require "went_hiking/models"
require "went_hiking/photo_metadata"
require "went_hiking/photo_variant_job"
require "went_hiking/s3_keys"
require "went_hiking/storage"

module WentHiking
  class PhotoUpload
    ALLOWED_CONTENT_TYPES = %w[image/jpeg image/jpg image/pjpeg image/png image/x-png image/gif].freeze
    MAX_BYTES = 10 * 1024 * 1024
    MIN_BYTES = 1024

    Result = Struct.new(:photo, :errors, keyword_init: true) do
      def success?
        errors.empty?
      end
    end

    def initialize(account:, trip:, upload:, caption:)
      @account = account
      @trip = trip
      @upload = upload
      @caption = caption.to_s.strip
    end

    def call
      errors = validation_errors
      return Result.new(errors: errors) unless errors.empty?

      photo = nil
      WentHiking.db.transaction do
        photo = create_photo
        key = S3Keys.photo_variant_key(photo_id: photo.id, style: "original", filename: clean_filename)
        Storage.current.put(key, io: tempfile, content_type: content_type)
        Models::PhotoVariant.create(
          photo_id: photo.id,
          style: "original",
          filename: File.basename(key),
          s3_key: key,
          file_size: file_size,
          created_at: Time.now,
          updated_at: Time.now
        )
        PhotoVariantJob.enqueue_photo(photo.id)
      end

      Result.new(photo: photo, errors: [])
    end

    private

    attr_reader :account, :trip, :upload, :caption

    def create_photo
      Models::Photo.create({
        account_id: account.id,
        trip_id: trip.id,
        legacy_image_file_name: clean_filename,
        content_type: content_type,
        file_size: file_size,
        caption: optional_string(caption),
        legacy_stats_added: true,
        created_at: Time.now,
        updated_at: Time.now
      }.merge(metadata))
    end

    def metadata
      @metadata ||= PhotoMetadata.extract(tempfile.path)
    rescue
      {}
    end

    def validation_errors
      errors = []
      errors << "Choose a photo to upload." unless tempfile
      errors << "Image files must be JPEG, PNG, or GIF." if tempfile && !ALLOWED_CONTENT_TYPES.include?(content_type)
      errors << "Image file is too small." if tempfile && file_size < MIN_BYTES
      errors << "Image file must be 10 MB or smaller." if tempfile && file_size > MAX_BYTES
      errors
    end

    def filename
      value = upload_value(:filename) || upload_value("filename") || upload_value(:original_filename) || "photo"
      File.basename(value.to_s)
    end

    def clean_filename
      @clean_filename ||= filename.gsub(%r{[^A-Za-z0-9._-]+}, "-")
    end

    def content_type
      (upload_value(:type) || upload_value("type") || upload_value(:content_type)).to_s
    end

    def tempfile
      upload_value(:tempfile) || upload_value("tempfile")
    end

    def file_size
      tempfile.size
    end

    def upload_value(key)
      if upload.respond_to?(:[])
        upload[key]
      elsif upload.respond_to?(key)
        upload.public_send(key)
      end
    end

    def optional_string(value)
      value.to_s.empty? ? nil : value
    end
  end
end
