# frozen_string_literal: true

require "mini_magick"
require "que"
require "tempfile"
require "went_hiking/models"
require "went_hiking/photo_metadata"
require "went_hiking/s3_keys"
require "went_hiking/storage"

module WentHiking
  class PhotoVariantJob < Que::Job
    STYLES = {
      "micro" => {resize: "25x25^", extent: "25x25", quality: 65},
      "thumbnail" => {resize: "125x125^", extent: "125x125", quality: 65},
      "bpl" => {resize: "550x900>", quality: 85},
      "large" => {resize: "900x1200>", quality: 85},
      "medium" => {resize: "300x300>", quality: 85}
    }.freeze

    def self.enqueue_photo(photo_id)
      return unless WentHiking.db.database_type == :postgres

      enqueue(photo_id)
    end

    def run(photo_id)
      photo = Models::Photo[photo_id]
      return unless photo

      original = photo.variant("original")
      return unless original&.s3_key

      with_original_file(original.s3_key) do |path|
        update_photo_metadata(photo, path)
        STYLES.each do |style, options|
          create_variant(photo, path, style, options)
        end
      end
    end

    private

    def with_original_file(key)
      Tempfile.create(["went-hiking-original", File.extname(key)]) do |file|
        file.binmode
        file.write(Storage.current.read(key))
        file.flush
        yield file.path
      end
    end

    def create_variant(photo, original_path, style, options)
      Tempfile.create(["went-hiking-#{style}", ".jpg"]) do |file|
        image = MiniMagick::Image.open(original_path)
        image.auto_orient
        image.combine_options do |command|
          command.resize options.fetch(:resize)
          if options[:extent]
            command.gravity "center"
            command.extent options.fetch(:extent)
          end
          command.quality options.fetch(:quality)
        end
        image.format "jpg"
        image.write file.path

        key = S3Keys.photo_variant_key(photo_id: photo.id, style: style, filename: derivative_filename(photo.legacy_image_file_name))
        File.open(file.path, "rb") do |io|
          Storage.current.put(key, io: io, content_type: "image/jpeg")
        end

        upsert_variant(photo, style, key, File.size(file.path))
      end
    end

    def update_photo_metadata(photo, original_path)
      metadata = PhotoMetadata.extract(original_path)
      photo.update(metadata) unless metadata.empty?
    rescue
      nil
    end

    def upsert_variant(photo, style, key, file_size)
      dataset = Models::PhotoVariant.where(photo_id: photo.id, style: style)
      values = {
        photo_id: photo.id,
        style: style,
        filename: File.basename(key),
        s3_key: key,
        file_size: file_size,
        updated_at: Time.now
      }

      if (variant = dataset.first)
        variant.update(values)
      else
        Models::PhotoVariant.create(values.merge(created_at: Time.now))
      end
    end

    def derivative_filename(filename)
      "#{File.basename(filename.to_s, ".*")}.jpg"
    end
  end
end
