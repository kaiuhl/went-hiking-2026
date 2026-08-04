# frozen_string_literal: true

require "tempfile"
require "vips"
require "went_hiking/image_format"
require "went_hiking/photo_file"
require "went_hiking/s3_keys"
require "went_hiking/storage"

module WentHiking
  class AvatarUpload
    MAX_BYTES = 5 * 1024 * 1024
    MIN_BYTES = 1024
    ACCEPTED_FORMATS = %i[jpeg png gif].freeze

    # Square center crops for everywhere an avatar renders (36px member rows,
    # the 132px profile ring), plus a capped original to re-derive from if the
    # styles ever change. Everything is transcoded to JPEG, which is also what
    # makes new uploads resolvable for imported members: avatar_url derives
    # legacy style filenames as "<stem>.jpg", so a stored name that already
    # ends in .jpg reads back identically through either branch.
    STYLES = {
      "original" => {width: 1200, height: 1200, crop: false, quality: 85},
      "medium" => {width: 300, height: 300, crop: true, quality: 85},
      "thumbnail" => {width: 125, height: 125, crop: true, quality: 65},
      "micro" => {width: 72, height: 72, crop: true, quality: 65}
    }.freeze

    Result = Struct.new(:errors) do
      def success?
        errors.empty?
      end
    end

    def self.present?(upload)
      new(account: nil, upload: upload).present?
    end

    # Clears the stored avatar and then deletes its files. Column order first:
    # a delete that dies half way must not leave the profile pointing at keys
    # that are gone.
    def self.remove(account)
      keys = stored_keys(account)
      account.update(avatar_file_name: nil, avatar_content_type: nil, avatar_file_size: nil)
      delete_keys(keys)
    end

    # The keys avatar_url resolves for what is stored right now. Imported
    # members keep their original's own extension with .jpg derivatives;
    # everything uploaded here is .jpg throughout, which makes the two
    # spellings coincide.
    def self.stored_keys(account)
      filename = account.avatar_file_name.to_s
      return [] if filename.empty? || filename.match?(%r{\Ahttps?://}i)

      STYLES.keys.map do |style|
        name = (account.legacy_user_id && style != "original") ? "#{File.basename(filename, ".*")}.jpg" : filename
        S3Keys.avatar_variant_key(account_id: account.legacy_user_id || account.id, style: style, filename: name)
      end.uniq
    end

    def self.delete_keys(keys)
      keys.each do |key|
        Storage.current.delete(key)
      rescue
        nil
      end
    end

    def initialize(account:, upload:)
      @account = account
      @upload = upload
    end

    def call
      return Result.new(errors: []) unless present?

      errors = validation_errors
      return Result.new(errors: errors) unless errors.empty?

      previous_keys = self.class.stored_keys(account)
      begin
        write_variants
      rescue Vips::Error
        return Result.new(errors: ["That image file could not be read. Try exporting it again as a JPEG."])
      end

      account.update(
        avatar_file_name: stored_filename,
        avatar_content_type: "image/jpeg",
        avatar_file_size: file_size
      )
      self.class.delete_keys(previous_keys - self.class.stored_keys(account))

      Result.new(errors: [])
    end

    def present?
      !tempfile.nil? && file_size.positive?
    end

    # The format check reads the bytes themselves — the browser's claimed
    # content type decides nothing, since everything stored is JPEG anyway.
    def validation_errors
      errors = []
      errors << "Profile photos must be JPEG, PNG, or GIF." unless ACCEPTED_FORMATS.include?(ImageFormat.sniff_io(tempfile))
      errors << "That image file is too small to be a photo." if file_size < MIN_BYTES
      errors << "Profile photos must be 5 MB or smaller." if file_size > MAX_BYTES
      errors
    end

    private

    attr_reader :account, :upload

    def write_variants
      STYLES.each do |style, options|
        Tempfile.create(["went-hiking-avatar-#{style}", ".jpg"]) do |file|
          # thumbnail applies the EXIF rotation itself; crop fills the square
          # from the center, size: :down only ever shrinks the original.
          image = Vips::Image.thumbnail(
            tempfile.path,
            options.fetch(:width),
            height: options.fetch(:height),
            **(options[:crop] ? {crop: :centre} : {size: :down})
          )
          image = image.flatten(background: [255, 255, 255]) if image.has_alpha?
          image.jpegsave(file.path, Q: options.fetch(:quality), strip: true)

          key = S3Keys.avatar_variant_key(account_id: account.legacy_user_id || account.id, style: style, filename: stored_filename)
          File.open(file.path, "rb") do |io|
            Storage.current.put(key, io: io, content_type: "image/jpeg")
          end
        end
      end
    end

    def filename
      value = upload_value(:filename) || upload_value("filename") || upload_value(:original_filename) || "avatar"
      File.basename(value.to_s)
    end

    def stored_filename
      @stored_filename ||= PhotoFile.stored_filename(filename, "image/jpeg")
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
