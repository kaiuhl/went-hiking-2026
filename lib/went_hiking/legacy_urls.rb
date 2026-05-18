# frozen_string_literal: true

require "went_hiking/slug"

module WentHiking
  module LegacyUrls
    module_function

    def person_path(account)
      "/people/#{Slug.id_slug(account.id, account.name || account.email)}"
    end

    def hike_path(trip)
      "/hikes/#{Slug.id_slug(trip.id, trip.name)}"
    end

    def photo_path(photo)
      "#{hike_path(photo.trip)}/photos/#{photo.id}"
    end

    def legacy_media_url(key)
      "#{WentHiking.media_base_url}/#{key.to_s.sub(%r{\A/+}, "")}"
    end
  end
end
