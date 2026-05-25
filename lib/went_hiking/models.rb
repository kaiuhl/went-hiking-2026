# frozen_string_literal: true

require_relative "../went_hiking/slug"
require_relative "../went_hiking/legacy_urls"

module WentHiking
  module Models
    Sequel::Model.db = WentHiking.db
    Sequel::Model.plugin :timestamps, update_on_create: true

    class Account < Sequel::Model(:accounts)
      one_to_many :trips
      one_to_many :photos
      one_to_many :comments
      one_to_many :hearts
      one_to_many :hike_follow_subscriptions, key: :followed_account_id
      one_to_many :hike_follow_notifications

      def before_validation
        self.slug ||= Slug.generate(name || email)
        super
      end

      def public_path
        LegacyUrls.person_path(self)
      end
    end

    class Trip < Sequel::Model(:trips)
      many_to_one :account
      one_to_many :photos
      one_to_many :comments
      one_to_many :hearts
      one_to_many :hike_follow_notifications

      dataset_module do
        def published
          where(status: "published")
        end

        def drafts
          where(status: "draft")
        end
      end

      def before_validation
        self.status ||= "published"
        self.slug ||= Slug.generate(name)
        super
      end

      def public_path
        LegacyUrls.hike_path(self)
      end

      def backpacking?
        nights.to_i.positive?
      end

      def draft?
        status == "draft"
      end

      def published?
        status == "published"
      end
    end

    class Photo < Sequel::Model(:photos)
      many_to_one :account
      many_to_one :trip
      one_to_many :photo_variants

      def public_path
        LegacyUrls.photo_path(self)
      end

      def variant(style)
        photo_variants_dataset.where(style: style.to_s).first
      end
    end

    class PhotoVariant < Sequel::Model(:photo_variants)
      many_to_one :photo

      def public_url
        LegacyUrls.legacy_media_url(s3_key || legacy_path)
      end
    end

    class Comment < Sequel::Model(:comments)
      many_to_one :account
      many_to_one :trip
    end

    class Heart < Sequel::Model(:hearts)
      many_to_one :account
      many_to_one :trip
    end

    class HikeFollowSubscription < Sequel::Model(:hike_follow_subscriptions)
      many_to_one :followed_account, class: "WentHiking::Models::Account", key: :followed_account_id
      one_to_many :hike_follow_notification_deliveries, key: :subscription_id

      dataset_module do
        def active
          where(status: "active")
        end
      end

      def active?
        status == "active"
      end

      def pending?
        status == "pending"
      end

      def unsubscribed?
        status == "unsubscribed"
      end
    end

    class HikeFollowNotification < Sequel::Model(:hike_follow_notifications)
      many_to_one :trip
      many_to_one :account
      one_to_many :hike_follow_notification_deliveries, key: :notification_id
    end

    class HikeFollowNotificationDelivery < Sequel::Model(:hike_follow_notification_deliveries)
      many_to_one :notification, class: "WentHiking::Models::HikeFollowNotification", key: :notification_id
      many_to_one :subscription, class: "WentHiking::Models::HikeFollowSubscription", key: :subscription_id
    end

    class ImportRun < Sequel::Model(:import_runs)
    end
  end
end
