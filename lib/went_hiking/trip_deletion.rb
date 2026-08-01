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
      storage = Storage.current
      photos.each { |photo| delete_photo_files(photo, storage: storage) }

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

    # Both backends implement #delete, so this is no longer local-only: on S3 a
    # deleted trip used to leave every one of its variants in the bucket
    # forever. Failures are logged rather than raised — an orphaned object costs
    # storage, but a trip that refuses to delete costs the hiker their trust.
    def delete_photo_files(photo, storage: Storage.current)
      photo.photo_variants_dataset.all.each do |variant|
        key = variant.s3_key.to_s
        next if key.empty?

        begin
          storage.delete(key)
        rescue => error
          warn("[went-hiking] could not delete stored object #{key}: #{error.class}: #{error.message}")
        end
      end
    end
  end
end
