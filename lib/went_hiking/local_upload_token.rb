# frozen_string_literal: true

require "openssl"

module WentHiking
  # Signed upload tickets for the local storage backend.
  #
  # The S3 backend authorizes browser uploads with a presigned POST policy. Local
  # storage has no such mechanism, so we mint the equivalent: an HMAC over the
  # destination key, content type, size bounds, and an expiry. The token is the
  # authorization for POST /uploads/direct, exactly like an S3 policy signature,
  # which is why that route does not require a session or a CSRF token.
  module LocalUploadToken
    UPLOAD_PATH = "/uploads/direct"
    DEFAULT_EXPIRES_IN = 900
    DEFAULT_SECRET = "development-session-secret-change-me-at-deploy-development-session-secret"
    SIGNED_FIELDS = %w[key content_type min_bytes max_bytes expires_at].freeze
    KEY_PATTERN = %r{\A[A-Za-z0-9][A-Za-z0-9._/-]*\z}
    ALLOWED_KEY_PREFIXES = %w[system/ uploads/].freeze

    Result = Struct.new(:key, :content_type, :min_bytes, :max_bytes, :error, keyword_init: true) do
      def valid?
        error.nil?
      end
    end

    module_function

    # Fields the browser must echo back with the multipart upload, mirroring the
    # shape of Aws::S3::PresignedPost#fields.
    def fields(key:, content_type:, min_bytes:, max_bytes:, expires_in: DEFAULT_EXPIRES_IN, now: Time.now)
      payload = {
        "key" => key.to_s,
        "content_type" => content_type.to_s,
        "min_bytes" => min_bytes.to_i.to_s,
        "max_bytes" => max_bytes.to_i.to_s,
        "expires_at" => (now.to_i + expires_in.to_i).to_s
      }

      payload.merge("token" => sign(payload))
    end

    def verify(params, now: Time.now)
      payload = SIGNED_FIELDS.each_with_object({}) { |field, memo| memo[field] = params[field].to_s }
      token = params["token"].to_s

      return Result.new(error: "Upload token is missing.") if token.empty?
      return Result.new(error: "Upload token is invalid.") unless secure_equal?(sign(payload), token)
      return Result.new(error: "Upload token has expired.") if payload["expires_at"].to_i <= now.to_i
      return Result.new(error: "Upload token is invalid.") unless allowed_key?(payload["key"])

      Result.new(
        key: payload["key"],
        content_type: payload["content_type"],
        min_bytes: payload["min_bytes"].to_i,
        max_bytes: payload["max_bytes"].to_i
      )
    end

    def sign(payload)
      message = SIGNED_FIELDS.map { |field| payload[field].to_s }.join("\n")
      OpenSSL::HMAC.hexdigest("SHA256", secret, message)
    end

    def secret
      value = ENV["LOCAL_UPLOAD_SECRET"] || ENV["RODAUTH_HMAC_SECRET"] || ENV["SESSION_SECRET"]
      value.to_s.strip.empty? ? DEFAULT_SECRET : value
    end

    # Defense in depth: the key is signed, but never trust a signed value blindly.
    def allowed_key?(key)
      value = key.to_s
      return false unless value.match?(KEY_PATTERN)
      return false if value.split("/").include?("..")
      return false unless ALLOWED_KEY_PREFIXES.any? { |prefix| value.start_with?(prefix) }

      true
    end

    def secure_equal?(expected, given)
      expected.bytesize == given.bytesize && OpenSSL.fixed_length_secure_compare(expected, given)
    end
  end
end
