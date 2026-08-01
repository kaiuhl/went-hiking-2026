# frozen_string_literal: true

require "aws-sdk-s3"
require "aws-sdk-s3/presigned_post"
require "fileutils"
require "went_hiking/local_upload_token"

module WentHiking
  module Storage
    module_function

    def current
      if ENV["UPLOAD_STORAGE"] == "local" || ENV["S3_BUCKET"].to_s.empty?
        Local.new(ENV.fetch("LOCAL_UPLOAD_ROOT", File.join(WentHiking.root, "tmp/uploads")))
      else
        S3.new(bucket: ENV.fetch("S3_BUCKET"), region: ENV.fetch("AWS_REGION", "us-west-2"))
      end
    end

    class Local
      class InvalidKey < StandardError; end

      def initialize(root)
        @root = root
      end

      def put(key, io:, content_type:)
        path = path_for!(key)
        FileUtils.mkdir_p(File.dirname(path))
        io.rewind if io.respond_to?(:rewind)
        File.open(path, "wb") { |file| IO.copy_stream(io, file) }
        path
      end

      def read(key)
        File.binread(path_for!(key))
      end

      # S3 has no directories, so a key that goes away leaves nothing behind. On
      # disk it leaves system/images/1234/original/ standing empty forever, and
      # a deleted trip leaves a whole tree of them.
      def delete(key)
        path = path_for(key)
        return unless path

        FileUtils.rm_f(path)
        prune_empty_dirs(File.dirname(path))
      end

      def direct_upload?
        true
      end

      def local?
        true
      end

      # Mirrors Storage::S3#direct_upload_post. The signed token stands in for the
      # S3 policy signature; POST /uploads/direct verifies it before writing.
      def direct_upload_post(key:, content_type:, min_bytes:, max_bytes:, expires_in: 900)
        {
          url: LocalUploadToken::UPLOAD_PATH,
          fields: LocalUploadToken.fields(
            key: key,
            content_type: content_type,
            min_bytes: min_bytes,
            max_bytes: max_bytes,
            expires_in: expires_in
          )
        }
      end

      def object_exists?(key)
        path = path_for(key)
        !path.nil? && File.file?(path)
      end

      # Absolute path for a key, or nil when the key would escape the upload root.
      def path_for(key)
        value = key.to_s
        return nil if value.empty? || value.include?("\0") || value.start_with?("/")
        return nil if value.split("/").include?("..")

        path = File.expand_path(File.join(root, value))
        return nil unless path.start_with?(root_prefix)

        path
      end

      private

      attr_reader :root

      # Walks up while the directory is empty and still strictly inside the
      # upload root, so the root itself always survives even when it is emptied.
      def prune_empty_dirs(dir)
        while dir.start_with?(root_prefix) && Dir.empty?(dir)
          Dir.rmdir(dir)
          dir = File.dirname(dir)
        end
      rescue SystemCallError
        nil
      end

      def path_for!(key)
        path_for(key) || raise(InvalidKey, "Storage key is outside the upload root: #{key.inspect}")
      end

      def root_prefix
        @root_prefix ||= File.expand_path(root) + File::SEPARATOR
      end
    end

    class S3
      def initialize(bucket:, region:)
        @bucket = bucket
        @client = Aws::S3::Client.new(region: region)
      end

      def put(key, io:, content_type:)
        io.rewind if io.respond_to?(:rewind)
        client.put_object(bucket: bucket, key: key, body: io, content_type: content_type)
        key
      end

      def read(key)
        client.get_object(bucket: bucket, key: key).body.read
      end

      def delete(key)
        client.delete_object(bucket: bucket, key: key)
      end

      def direct_upload?
        true
      end

      def local?
        false
      end

      def direct_upload_post(key:, content_type:, min_bytes:, max_bytes:, expires_in: 900)
        post = resource.bucket(bucket).presigned_post(
          key: key,
          content_type: content_type,
          content_length_range: min_bytes..max_bytes,
          signature_expiration: Time.now + expires_in,
          success_action_status: "201"
        )

        {url: post.url, fields: post.fields}
      end

      def object_exists?(key)
        client.head_object(bucket: bucket, key: key)
        true
      rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchKey
        false
      end

      private

      attr_reader :bucket, :client

      def resource
        @resource ||= Aws::S3::Resource.new(client: client)
      end
    end
  end
end
