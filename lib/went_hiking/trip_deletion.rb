# frozen_string_literal: true

require "went_hiking/models"
require "went_hiking/storage"

module WentHiking
  # Removes a trip and everything hanging off it. The database cascades on
  # delete, but photo files are outside the database, so children are walked
  # explicitly and stored objects are removed first.
  module TripDeletion
    module_function

    def call(trip)
      photos = trip.photos_dataset.all
      photos.each { |photo| delete_photo_files(photo) }

      WentHiking.db.transaction do
        photos.each do |photo|
          photo.photo_variants_dataset.delete
          photo.destroy
        end

        trip.hearts_dataset.delete
        trip.comments_dataset.delete
        trip.hike_follow_notifications_dataset.all.each do |notification|
          notification.hike_follow_notification_deliveries_dataset.delete
          notification.destroy
        end

        trip.destroy
      end

      true
    end

    def delete_photo_files(photo)
      storage = Storage.current
      return unless storage.local?

      photo.photo_variants_dataset.all.each do |variant|
        key = variant.s3_key.to_s
        next if key.empty?

        storage.delete(key)
      end
    rescue
      nil
    end
  end
end
