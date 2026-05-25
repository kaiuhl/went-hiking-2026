# frozen_string_literal: true

require "went_hiking/follow_subscription_request"
require "went_hiking/follow_tokens"
require "went_hiking/models"

module FollowRoutes
  def route_follows(r)
    r.on "follow" do
      r.get "confirm", String do |token|
        subscription = WentHiking::Models::HikeFollowSubscription.first(confirmation_token_digest: WentHiking::FollowTokens.digest(token))

        if subscription
          subscription.update(
            status: "active",
            confirmation_token_digest: nil,
            confirmed_at: Time.now,
            unsubscribed_at: nil,
            updated_at: Time.now
          )
          follow_notice(
            title: "Follow confirmed",
            message: "You will get an email the morning after #{subscription.followed_account.name} posts a new hike.",
            action_url: subscription.followed_account.public_path,
            action_label: "View #{subscription.followed_account.name}"
          )
        else
          response.status = 404
          follow_notice(
            title: "Follow link expired",
            message: "That confirmation link is no longer active. You can request a fresh one from the hiker's profile.",
            action_url: "/hikes",
            action_label: "View recent hikes"
          )
        end
      end

      r.get "unsubscribe", String do |token|
        subscription = WentHiking::FollowTokens.subscription_from_token(token, purpose: "unsubscribe")

        if subscription
          subscription.update(
            status: "unsubscribed",
            confirmation_token_digest: nil,
            unsubscribed_at: Time.now,
            updated_at: Time.now
          )
          follow_notice(
            title: "Unsubscribed",
            message: "You will no longer get emails when #{subscription.followed_account.name} posts new hikes.",
            action_url: subscription.followed_account.public_path,
            action_label: "View #{subscription.followed_account.name}"
          )
        else
          response.status = 404
          follow_notice(
            title: "Unsubscribe link expired",
            message: "That unsubscribe link is no longer active.",
            action_url: "/",
            action_label: "Go home"
          )
        end
      end
    end
  end

  private

  def follow_notice(title:, message:, action_url:, action_label:)
    @title = title
    @follow_title = title
    @follow_message = message
    @follow_action_url = action_url
    @follow_action_label = action_label
    view("follows/show")
  end
end
