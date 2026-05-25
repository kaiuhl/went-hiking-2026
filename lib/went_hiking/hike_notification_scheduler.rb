# frozen_string_literal: true

require "went_hiking/hike_notification_job"
require "went_hiking/hike_notification_schedule"
require "went_hiking/models"

module WentHiking
  module HikeNotificationScheduler
    module_function

    def schedule_trip(trip, now: Time.now)
      subscriptions = Models::HikeFollowSubscription.active.where(followed_account_id: trip.account_id).all
      return nil if subscriptions.empty?

      scheduled_at = HikeNotificationSchedule.next_morning_after(now: now)
      notification = nil

      WentHiking.db.transaction do
        notification = Models::HikeFollowNotification.where(trip_id: trip.id).first ||
          Models::HikeFollowNotification.create(
            trip_id: trip.id,
            account_id: trip.account_id,
            scheduled_at: scheduled_at,
            created_at: now,
            updated_at: now
          )

        subscriptions.each do |subscription|
          next if Models::HikeFollowNotificationDelivery.where(notification_id: notification.id, subscription_id: subscription.id).any?

          Models::HikeFollowNotificationDelivery.create(
            notification_id: notification.id,
            subscription_id: subscription.id,
            email: subscription.email,
            status: "pending",
            created_at: now,
            updated_at: now
          )
        end

        enqueue_notification(notification) if WentHiking.db.database_type == :postgres
      end

      notification
    end

    def enqueue_notification(notification)
      HikeNotificationJob.enqueue(notification.id, job_options: {run_at: notification.scheduled_at})
    end
  end
end
