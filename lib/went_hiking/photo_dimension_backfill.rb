# frozen_string_literal: true

require "tempfile"
require "went_hiking/models"
require "went_hiking/photo_metadata"
require "went_hiking/storage"

module WentHiking
  # Fills in width and height for rows that predate the uploader recording them.
  #
  # Everything is read through Storage, so this is the same task on a laptop with
  # files under tmp/uploads and in production with them in S3. Rows whose only
  # location is a legacy absolute URL are skipped rather than fetched: those
  # files live on the old host, are never re-served from here, and the grids
  # already reserve space for them on their own.
  module PhotoDimensionBackfill
    Result = Struct.new(:variants, :photos, :skipped, :missing, :failed, keyword_init: true) do
      def to_s
        "variants: #{variants}, photos: #{photos}, skipped (no local key): #{skipped}, " \
          "missing from storage: #{missing}, unreadable: #{failed}"
      end
    end

    module_function

    def call(storage: Storage.current, logger: nil)
      result = Result.new(variants: 0, photos: 0, skipped: 0, missing: 0, failed: 0)

      pending_variants.each do |variant|
        backfill_variant(variant, storage, result, logger)
      end

      pending_photos.each do |photo|
        result.photos += 1 if backfill_photo(photo)
      end

      result
    end

    def pending_variants
      Models::PhotoVariant.where(Sequel.|({width: nil}, {height: nil})).order(:id)
    end

    def pending_photos
      Models::Photo.where(Sequel.|({width: nil}, {height: nil})).order(:id)
    end

    # A photo's own dimensions describe the file the hiker uploaded, so they come
    # from the original variant and nowhere else.
    def backfill_photo(photo)
      original = photo.variant("original")
      return false unless original
      return false unless original.width.to_i.positive? && original.height.to_i.positive?

      photo.update(width: original.width, height: original.height, updated_at: Time.now)
      true
    end

    def backfill_variant(variant, storage, result, logger)
      key = variant.s3_key.to_s
      if key.empty? || key.match?(%r{\A[a-z][a-z0-9+.-]*://}i)
        result.skipped += 1
        return
      end

      unless storage.object_exists?(key)
        result.missing += 1
        return
      end

      width, height = dimensions_for(storage, key)
      unless width.to_i.positive? && height.to_i.positive?
        result.failed += 1
        return
      end

      variant.update(width: width, height: height, updated_at: Time.now)
      result.variants += 1
      logger&.call("#{key} -> #{width}x#{height}")
    rescue => error
      result.failed += 1
      logger&.call("could not read #{key}: #{error.class}: #{error.message}")
    end

    def dimensions_for(storage, key)
      Tempfile.create(["went-hiking-backfill", File.extname(key)]) do |file|
        file.binmode
        file.write(storage.read(key))
        file.flush
        PhotoMetadata.dimensions(file.path)
      end
    end
  end
end
