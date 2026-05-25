# frozen_string_literal: true

require "digest"
require "openssl"
require "rack/utils"
require "securerandom"
require "went_hiking/models"

module WentHiking
  module FollowTokens
    module_function

    def random_token
      SecureRandom.urlsafe_base64(32)
    end

    def digest(token)
      Digest::SHA256.hexdigest(token.to_s)
    end

    def unsubscribe_token(subscription)
      signed_subscription_token(subscription.id, purpose: "unsubscribe")
    end

    def subscription_from_token(token, purpose:)
      id, signature = token.to_s.split("-", 2)
      return nil unless id&.match?(/\A\d+\z/) && signature

      expected = signature_for(id, purpose: purpose)
      return nil unless secure_compare(signature, expected)

      Models::HikeFollowSubscription[id.to_i]
    end

    def public_url(path)
      "#{WentHiking.public_base_url.to_s.sub(%r{/+\z}, "")}/#{path.to_s.sub(%r{\A/+}, "")}"
    end

    def signed_subscription_token(subscription_id, purpose:)
      id = subscription_id.to_i.to_s
      "#{id}-#{signature_for(id, purpose: purpose)}"
    end

    def signature_for(id, purpose:)
      OpenSSL::HMAC.hexdigest("SHA256", secret, "#{purpose}:#{id}")
    end

    def secure_compare(left, right)
      return false unless left.bytesize == right.bytesize

      Rack::Utils.secure_compare(left, right)
    end

    def secret
      ENV.fetch(
        "FOLLOW_TOKEN_SECRET",
        ENV.fetch(
          "RODAUTH_HMAC_SECRET",
          ENV.fetch("SESSION_SECRET", "development-session-secret-change-me-at-deploy-development-session-secret")
        )
      )
    end
  end
end
