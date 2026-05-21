# frozen_string_literal: true

require "went_hiking/s3_keys"
require "went_hiking/storage"

module WentHiking
  class AvatarUpload
    ALLOWED_CONTENT_TYPES = %w[image/jpeg image/jpg image/pjpeg image/png image/x-png image/gif].freeze
    MAX_BYTES = 5 * 1024 * 1024
    MIN_BYTES = 1024
    STYLES = %w[original micro thumbnail medium].freeze

    Result = Struct.new(:errors, keyword_init: true) do
      def success?
        errors.empty?
      end
    end

    def self.present?(upload)
      new(account: nil, upload: upload).present?
    end

    def initialize(account:, upload:)
      @account = account
      @upload = upload
    end

    def call
      return Result.new(errors: []) unless present?

      errors = validation_errors
      return Result.new(errors: errors) unless errors.empty?

      STYLES.each do |style|
        Storage.current.put(avatar_key(style), io: tempfile, content_type: content_type)
      end

      account.update(
        avatar_file_name: clean_filename,
        avatar_content_type: content_type,
        avatar_file_size: file_size
      )

      Result.new(errors: [])
    end

    def present?
      tempfile && file_size.positive?
    end

    private

    attr_reader :account, :upload

    def validation_errors
      errors = []
      errors << "Avatar must be JPEG, PNG, or GIF." unless ALLOWED_CONTENT_TYPES.include?(content_type)
      errors << "Avatar image is too small." if file_size < MIN_BYTES
      errors << "Avatar image must be 5 MB or smaller." if file_size > MAX_BYTES
      errors
    end

    def avatar_key(style)
      S3Keys.avatar_variant_key(account_id: account.id, style: style, filename: clean_filename)
    end

    def filename
      value = upload_value(:filename) || upload_value("filename") || upload_value(:original_filename) || "avatar"
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
      if upload.respond_to?(:key?) && upload.key?(key)
        upload[key]
      elsif upload.respond_to?(:key?) && upload.key?(key.to_s)
        upload[key.to_s]
      elsif upload.respond_to?(key)
        upload.public_send(key)
      end
    end
  end
end
