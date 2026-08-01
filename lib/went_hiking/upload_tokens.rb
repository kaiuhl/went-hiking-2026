# frozen_string_literal: true

require "openssl"
require "rack/utils"
require "went_hiking/models"

module WentHiking
  # Signed, expiring tokens that let a trip owner upload photos from a device
  # without a logged-in session -- used by the MCP photo upload link, which
  # people open on their phone straight from a chat conversation.
  module UploadTokens
    PURPOSE = "trip-photo-upload"
    TTL_SECONDS = 2 * 60 * 60

    module_function

    def generate(trip, now: Time.now)
      expires_at = (now + TTL_SECONDS).to_i
      "#{trip.id}.#{expires_at}.#{signature_for(trip.id, expires_at)}"
    end

    def trip_from(token, now: Time.now)
      trip_id, expires_at, signature = token.to_s.split(".", 3)
      return nil unless trip_id&.match?(/\A\d+\z/) && expires_at&.match?(/\A\d+\z/) && signature
      return nil if expires_at.to_i < now.to_i

      expected = signature_for(trip_id.to_i, expires_at.to_i)
      return nil unless secure_compare(signature, expected)

      Models::Trip[trip_id.to_i]
    end

    def upload_url(trip, now: Time.now)
      token = generate(trip, now: now)
      base = WentHiking.public_base_url.to_s.sub(%r{/+\z}, "")
      "#{base}#{trip.public_path}/photos/mobile-upload?token=#{token}"
    end

    def expires_at(now: Time.now)
      now + TTL_SECONDS
    end

    def signature_for(trip_id, expires_at)
      OpenSSL::HMAC.hexdigest("SHA256", secret, "#{PURPOSE}:#{trip_id}:#{expires_at}")
    end

    def secure_compare(left, right)
      return false unless left.bytesize == right.bytesize

      Rack::Utils.secure_compare(left, right)
    end

    # An env var exported as an empty string is a var nobody filled in, not a
    # request for an empty HMAC key, so a blank one falls through to the next
    # name rather than ending the search. The last rung is a secret committed to
    # this repository, which is why production refuses to boot without
    # SESSION_SECRET — that check is what keeps this from ever being reached
    # anywhere it would matter.
    SECRET_ENV_VARS = %w[UPLOAD_TOKEN_SECRET RODAUTH_HMAC_SECRET SESSION_SECRET].freeze
    DEFAULT_SECRET = "development-session-secret-change-me-at-deploy-development-session-secret"

    def secret
      name = SECRET_ENV_VARS.find { |key| !ENV[key].to_s.strip.empty? }
      name ? ENV[name] : DEFAULT_SECRET
    end
  end
end
