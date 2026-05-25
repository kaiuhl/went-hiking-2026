# frozen_string_literal: true

require "went_hiking/follow_email"
require "went_hiking/follow_tokens"
require "went_hiking/models"

module WentHiking
  class FollowSubscriptionRequest
    EMAIL_PATTERN = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

    class Result
      attr_reader :errors, :subscription

      def initialize(success:, errors:, subscription: nil, email_sent: false)
        @success = success
        @errors = errors
        @subscription = subscription
        @email_sent = email_sent
      end

      def success?
        @success
      end

      def email_sent?
        @email_sent
      end
    end

    def initialize(account:, email:, honeypot: nil, now: Time.now)
      @account = account
      @email = normalize_email(email)
      @honeypot = honeypot.to_s
      @now = now
    end

    def call
      return Result.new(success: true, errors: [], email_sent: false) unless honeypot.empty?
      return Result.new(success: false, errors: ["Enter a valid email address."], email_sent: false) unless valid_email?

      token = nil
      email_sent = false
      subscription = nil

      WentHiking.db.transaction do
        subscription = Models::HikeFollowSubscription.where(followed_account_id: account.id, email: email).first
        if subscription&.active?
          email_sent = false
        elsif subscription
          token = reset_pending_subscription(subscription)
          email_sent = true
        else
          token = FollowTokens.random_token
          subscription = Models::HikeFollowSubscription.create(
            followed_account_id: account.id,
            email: email,
            status: "pending",
            confirmation_token_digest: FollowTokens.digest(token),
            confirmation_sent_at: now,
            created_at: now,
            updated_at: now
          )
          email_sent = true
        end
      end

      Email.deliver(FollowEmail.confirmation(subscription: subscription, token: token)) if email_sent
      Result.new(success: true, errors: [], subscription: subscription, email_sent: email_sent)
    end

    private

    attr_reader :account, :email, :honeypot, :now

    def reset_pending_subscription(subscription)
      token = FollowTokens.random_token
      subscription.update(
        status: "pending",
        confirmation_token_digest: FollowTokens.digest(token),
        confirmation_sent_at: now,
        confirmed_at: nil,
        unsubscribed_at: nil,
        updated_at: now
      )
      token
    end

    def normalize_email(value)
      value.to_s.strip.downcase
    end

    def valid_email?
      email.match?(EMAIL_PATTERN)
    end
  end
end
