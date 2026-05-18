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

      def before_validation
        self.slug ||= Slug.generate(name)
        super
      end

      def public_path
        LegacyUrls.hike_path(self)
      end

      def backpacking?
        nights.to_i.positive?
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

    class ImportRun < Sequel::Model(:import_runs)
    end
  end
end
