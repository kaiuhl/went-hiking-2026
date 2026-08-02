# frozen_string_literal: true

require "went_hiking/image_format"

module WentHiking
  module PhotoFile
    ALLOWED_CONTENT_TYPES = %w[image/jpeg image/jpg image/pjpeg image/png image/x-png image/gif].freeze
    MAX_BYTES = 20 * 1024 * 1024
    MIN_BYTES = 1024
    # An extension nothing will ever be served as an active type, for anything we
    # cannot name. Reachable only if a caller skips validation.
    FALLBACK_EXTENSION = ".bin"

    module_function

    def clean_filename(value)
      filename = File.basename(value.to_s.empty? ? "photo" : value.to_s)
      filename.gsub(%r{[^A-Za-z0-9._-]+}, "-")
    end

    # The name an upload is stored under. The stem is the uploader's, but the
    # extension comes from the content type we validated, because the extension
    # is what decides the Content-Type the file is later served with — and a
    # client-chosen ".svg" on a file we agreed to call an image is a script on
    # our own origin.
    def stored_filename(value, content_type)
      stem = File.basename(clean_filename(value), ".*").sub(/\A\.+/, "")
      stem = "photo" if stem.empty?

      "#{stem}#{ImageFormat.extension_for(content_type) || FALLBACK_EXTENSION}"
    end

    def validation_errors(filename:, content_type:, file_size:)
      errors = []
      errors << "Choose a photo to upload." if filename.to_s.strip.empty?
      errors << "Image files must be JPEG, PNG, or GIF." unless ALLOWED_CONTENT_TYPES.include?(content_type.to_s)
      errors << "Image file is too small." if file_size && file_size < MIN_BYTES
      errors << "Image file must be #{MAX_BYTES / (1024 * 1024)} MB or smaller." if file_size && file_size > MAX_BYTES
      errors << "Image file size is missing." unless file_size
      errors
    end
  end
end
