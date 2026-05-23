# frozen_string_literal: true

require "went_hiking/models"
require "went_hiking/photo_file"
require "went_hiking/photo_metadata"
require "went_hiking/photo_variant_job"
require "went_hiking/s3_keys"
require "went_hiking/storage"
require "tempfile"

module WentHiking
  class DirectPhotoUpload
    Result = Struct.new(:photo, :upload, :errors, keyword_init: true) do
      def success?
        errors.empty?
      end
    end

    FinalizeResult = Struct.new(:photo, :errors, keyword_init: true) do
      def success?
        errors.empty?
      end
    end

    def initialize(account:, trip:, filename:, content_type:, file_size:, caption:)
      @account = account
      @trip = trip
      @filename = filename.to_s
      @content_type = content_type.to_s
      @file_size = parse_file_size(file_size)
      @caption = caption.to_s.strip
    end

    def call
      storage = Storage.current
      errors = validation_errors(storage)
      return Result.new(errors: errors) unless errors.empty?

      photo = nil
      upload = nil

      WentHiking.db.transaction do
        photo = create_photo
        key = S3Keys.photo_variant_key(photo_id: photo.id, style: "original", filename: clean_filename)

        Models::PhotoVariant.create(
          photo_id: photo.id,
          style: "original",
          filename: File.basename(key),
          s3_key: key,
          file_size: file_size,
          created_at: Time.now,
          updated_at: Time.now
        )

        upload = storage.direct_upload_post(
          key: key,
          content_type: content_type,
          min_bytes: PhotoFile::MIN_BYTES,
          max_bytes: PhotoFile::MAX_BYTES
        )
      end

      Result.new(photo: photo, upload: upload, errors: [])
    end

    def self.finalize(account:, trip:, photo_id:)
      photo = trip.photos_dataset.where(id: photo_id, account_id: account.id).first
      return FinalizeResult.new(errors: ["Photo upload was not found."]) unless photo

      original = photo.variant("original")
      return FinalizeResult.new(errors: ["Photo upload is missing its original file."]) unless original&.s3_key
      storage = Storage.current
      return FinalizeResult.new(errors: ["Photo upload has not reached storage yet."]) unless storage.object_exists?(original.s3_key)

      metadata = metadata_for(storage, original.s3_key)
      photo.update(metadata) unless metadata.empty?

      PhotoVariantJob.enqueue_photo(photo.id)
      FinalizeResult.new(photo: photo, errors: [])
    rescue
      storage&.delete(original.s3_key) if original&.s3_key
      photo&.destroy
      FinalizeResult.new(errors: ["Image file could not be read."])
    end

    def self.metadata_for(storage, key)
      Tempfile.create(["went-hiking-direct-upload", File.extname(key)]) do |file|
        file.binmode
        file.write(storage.read(key))
        file.flush
        PhotoMetadata.extract(file.path)
      end
    end

    private_class_method :metadata_for

    private

    attr_reader :account, :trip, :filename, :content_type, :file_size, :caption

    def validation_errors(storage)
      errors = PhotoFile.validation_errors(filename: filename, content_type: content_type, file_size: file_size)
      errors << "Direct photo upload is not available in this environment." unless storage.direct_upload?
      errors
    end

    def create_photo
      Models::Photo.create(
        account_id: account.id,
        trip_id: trip.id,
        legacy_image_file_name: clean_filename,
        content_type: content_type,
        file_size: file_size,
        caption: optional_string(caption),
        legacy_stats_added: true,
        created_at: Time.now,
        updated_at: Time.now
      )
    end

    def clean_filename
      @clean_filename ||= PhotoFile.clean_filename(filename)
    end

    def parse_file_size(value)
      Integer(value, 10)
    rescue ArgumentError, TypeError
      nil
    end

    def optional_string(value)
      value.to_s.empty? ? nil : value
    end
  end
end
