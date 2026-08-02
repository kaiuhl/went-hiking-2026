# frozen_string_literal: true

require "que"
require "tempfile"
require "vips"
require "went_hiking/models"
require "went_hiking/photo_metadata"
require "went_hiking/s3_keys"
require "went_hiking/storage"

module WentHiking
  class PhotoVariantJob < Que::Job
    # libvips rather than ImageMagick: it decodes at the target scale in
    # streamed strips instead of inflating the full bitmap, which is the
    # difference between tens of megabytes and hundreds per photo — a
    # difference this app has felt.
    #
    # crop: true fills the exact box from the center (ImageMagick's "^" plus
    # extent); without it the image fits inside the box and only ever shrinks
    # (ImageMagick's ">").
    STYLES = {
      "micro" => {width: 25, height: 25, crop: true, quality: 65},
      "thumbnail" => {width: 125, height: 125, crop: true, quality: 65},
      "bpl" => {width: 550, height: 900, quality: 85},
      "large" => {width: 900, height: 1200, quality: 85},
      "medium" => {width: 300, height: 300, quality: 85}
    }.freeze

    def self.enqueue_photo(photo_id)
      return unless WentHiking.db.database_type == :postgres

      enqueue(photo_id)
    end

    # Runs the job body on the current thread. Used by the local storage path,
    # where there is no worker process and photos should appear immediately.
    # Variant failures are never fatal: the original is already stored and the
    # view helpers fall back to it.
    def self.generate_photo_now(photo_id)
      allocate.run(photo_id)
      true
    rescue => error
      warn("[went-hiking] photo variant generation failed for photo #{photo_id}: #{error.class}: #{error.message}")
      false
    end

    def run(photo_id)
      photo = Models::Photo[photo_id]
      return unless photo

      original = photo.variant("original")
      return unless original&.s3_key

      with_original_file(original.s3_key) do |path|
        update_photo_metadata(photo, path)
        record_original_dimensions(original, path)
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
        # thumbnail applies the EXIF rotation itself, so the dimensions it
        # reports are already what a browser will lay out.
        image = Vips::Image.thumbnail(
          original_path,
          options.fetch(:width),
          height: options.fetch(:height),
          **(options[:crop] ? {crop: :centre} : {size: :down})
        )
        # JPEG has no alpha; flatten transparent PNGs onto white rather than
        # letting the encoder pick a background.
        image = image.flatten(background: [255, 255, 255]) if image.has_alpha?
        image.jpegsave(file.path, Q: options.fetch(:quality), strip: true)

        key = S3Keys.photo_variant_key(photo_id: photo.id, style: style, filename: derivative_filename(photo.legacy_image_file_name))
        File.open(file.path, "rb") do |io|
          Storage.current.put(key, io: io, content_type: "image/jpeg")
        end

        upsert_variant(photo, style, key, File.size(file.path), [image.width, image.height])
      end
    end

    def update_photo_metadata(photo, original_path)
      metadata = PhotoMetadata.extract(original_path)
      photo.update(metadata) unless metadata.empty?
    rescue
      nil
    end

    # The original's row is written before its bytes exist, so it is the one
    # variant whose dimensions can only be filled in once the file has landed.
    def record_original_dimensions(original, path)
      width, height = PhotoMetadata.dimensions(path)
      return unless width.to_i.positive? && height.to_i.positive?

      original.update(width: width, height: height, updated_at: Time.now)
    rescue
      nil
    end

    def upsert_variant(photo, style, key, file_size, dimensions)
      dataset = Models::PhotoVariant.where(photo_id: photo.id, style: style)
      values = {
        photo_id: photo.id,
        style: style,
        filename: File.basename(key),
        s3_key: key,
        file_size: file_size,
        width: dimensions[0],
        height: dimensions[1],
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
