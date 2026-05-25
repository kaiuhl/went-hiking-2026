# frozen_string_literal: true

require "went_hiking/email"
require "went_hiking/follow_tokens"

module WentHiking
  module FollowEmail
    module_function

    def confirmation(subscription:, token:)
      account = subscription.followed_account
      confirm_url = FollowTokens.public_url("/follow/confirm/#{token}")

      Email.render_template(
        to: subscription.email,
        subject: "Follow #{account.name} on Went Hiking",
        headline: "Follow #{account.name}'s hikes",
        intro: "Confirm that you want an email the morning after #{account.name} posts a new hike.",
        cta_label: "Confirm follow",
        cta_url: confirm_url,
        outro: "If you did not ask to follow #{account.name}, you can ignore this email."
      )
    end

    def hike_notification(subscription:, trip:)
      account = trip.account
      unsubscribe_url = FollowTokens.public_url("/follow/unsubscribe/#{FollowTokens.unsubscribe_token(subscription)}")

      Email.render_template(
        to: subscription.email,
        subject: "#{account.name} posted a new hike: #{trip.name}",
        headline: "#{account.name} posted #{trip.name}",
        intro: notification_intro(trip),
        cta_label: "Read the hike",
        cta_url: FollowTokens.public_url(trip.public_path),
        outro: "You are getting this because you asked to follow #{account.name}'s hikes.",
        unsubscribe_url: unsubscribe_url
      )
    end

    def notification_intro(trip)
      parts = [
        trip_date_label(trip),
        number_label(trip.mileage, "miles"),
        number_label(trip.elevation, "feet gained"),
        night_count_label(trip.nights)
      ].compact.reject(&:empty?)

      intro = parts.empty? ? "A new hike is ready to read." : parts.join(" / ")
      excerpt = plain_excerpt(trip.report_markdown)
      excerpt.empty? ? intro : "#{intro}\n\n#{excerpt}"
    end

    def plain_excerpt(markdown)
      markdown.to_s
        .gsub(/\[([^\]]+)\]\([^)]+\)/, "\\1")
        .gsub(/[`*_>#-]+/, " ")
        .gsub(/\s+/, " ")
        .strip[0, 240].to_s
    end

    def trip_date_label(trip)
      start = trip.hiked_at
      return nil unless start

      if trip.nights.to_i.positive?
        finish = start + (trip.nights.to_i * 86_400)
        "#{start.strftime("%B %-d")} to #{finish.strftime("%B %-d, %Y")}"
      else
        start.strftime("%B %-d, %Y")
      end
    end

    def number_label(value, unit)
      return nil if value.nil?

      "#{format_number(value)} #{unit}"
    end

    def night_count_label(value)
      count = value.to_i
      return nil unless count.positive?

      "#{format_number(count)} #{(count == 1) ? "night" : "nights"}"
    end

    def format_number(value)
      number = value.to_f
      string = (number % 1).zero? ? number.to_i.to_s : number.to_s
      integer, decimal = string.split(".", 2)
      integer = integer.reverse.scan(/.{1,3}/).join(",").reverse
      [integer, decimal].compact.join(".")
    end
  end
end
