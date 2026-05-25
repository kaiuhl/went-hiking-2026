# frozen_string_literal: true

require "que"
require "went_hiking/follow_email"
require "went_hiking/models"

module WentHiking
  class HikeNotificationJob < Que::Job
    def run(notification_id)
      notification = Models::HikeFollowNotification[notification_id]
      return unless notification

      errors = []
      notification.hike_follow_notification_deliveries_dataset.where(status: "pending").each do |delivery|
        deliver_one(delivery, notification.trip, errors)
      end

      raise errors.first if errors.any?

      notification.update(sent_at: Time.now, updated_at: Time.now)
    end

    private

    def deliver_one(delivery, trip, errors)
      subscription = delivery.subscription
      unless subscription&.active?
        delivery.update(status: "skipped", updated_at: Time.now)
        return
      end

      Email.deliver(FollowEmail.hike_notification(subscription: subscription, trip: trip))
      delivery.update(status: "sent", sent_at: Time.now, last_error: nil, updated_at: Time.now)
    rescue => error
      delivery.update(last_error: "#{error.class}: #{error.message}", updated_at: Time.now)
      errors << error
    end
  end
end
