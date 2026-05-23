# frozen_string_literal: true

module WentHiking
  module PhotoFile
    ALLOWED_CONTENT_TYPES = %w[image/jpeg image/jpg image/pjpeg image/png image/x-png image/gif].freeze
    MAX_BYTES = 10 * 1024 * 1024
    MIN_BYTES = 1024

    module_function

    def clean_filename(value)
      filename = File.basename(value.to_s.empty? ? "photo" : value.to_s)
      filename.gsub(%r{[^A-Za-z0-9._-]+}, "-")
    end

    def validation_errors(filename:, content_type:, file_size:)
      errors = []
      errors << "Choose a photo to upload." if filename.to_s.strip.empty?
      errors << "Image files must be JPEG, PNG, or GIF." unless ALLOWED_CONTENT_TYPES.include?(content_type.to_s)
      errors << "Image file is too small." if file_size && file_size < MIN_BYTES
      errors << "Image file must be 10 MB or smaller." if file_size && file_size > MAX_BYTES
      errors << "Image file size is missing." unless file_size
      errors
    end
  end
end
