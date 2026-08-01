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
      # Ordered to match the `photos_dataset.order(:taken_at, :id)` every caller
      # was writing out by hand, so a listing can eager-load the association and
      # get the same sequence it used to pay a query per row for.
      one_to_many :photos, order: [:taken_at, :id]
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

        # One row of totals for the whole archive instead of one model per trip.
        # `count` is the row count; the sums skip NULLs, which is what summing
        # `mileage.to_f` and `nights.to_i` in Ruby did too.
        def totals
          aggregate = select {
            [
              count(:id).as(:trip_count),
              sum(:mileage).as(:mileage_total),
              sum(:nights).as(:nights_total)
            ]
          }
          row = aggregate.first || {}

          {
            trips: row[:trip_count].to_i,
            miles: row[:mileage_total].to_f,
            nights: row[:nights_total].to_i
          }
        end

        # Half-open range rather than `EXTRACT(year FROM hiked_at) = ?`: a bare
        # column is what lets the (account_id, hiked_at) index serve the lookup.
        def in_year(year)
          start_at = Time.utc(year, 1, 1)
          where { (hiked_at >= start_at) & (hiked_at < Time.utc(year + 1, 1, 1)) }
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

      # A listing eager-loads every variant of every photo it shows, and a photo
      # is asked for two or three styles apiece. Once the collection is in hand,
      # picking one out of it is what stops each ask from being its own query;
      # on a photo loaded by itself the dataset lookup is still the cheap answer.
      def variant(style)
        wanted = style.to_s
        loaded = associations[:photo_variants]
        return loaded.find { |variant| variant.style == wanted } if loaded

        photo_variants_dataset.where(style: wanted).first
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
