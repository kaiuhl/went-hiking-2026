# frozen_string_literal: true

require "aws-sdk-s3"
require "fileutils"

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
      def initialize(root)
        @root = root
      end

      def put(key, io:, content_type:)
        path = File.join(root, key)
        FileUtils.mkdir_p(File.dirname(path))
        io.rewind if io.respond_to?(:rewind)
        File.open(path, "wb") { |file| IO.copy_stream(io, file) }
        path
      end

      def read(key)
        File.binread(File.join(root, key))
      end

      private

      attr_reader :root
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

      private

      attr_reader :bucket, :client
    end
  end
end
