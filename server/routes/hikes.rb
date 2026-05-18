# frozen_string_literal: true

require "went_hiking/slug"

module HikeRoutes
  def route_hikes(r)
    r.on "hikes" do
      r.get Integer do |legacy_id|
        trip = WentHiking::Models::Trip.where(legacy_trip_id: legacy_id).first || WentHiking::Models::Trip[legacy_id]
        not_found unless trip
        redirect trip.public_path
      end

      r.get String, "photos", Integer do |trip_slug, photo_id|
        @trip = trip_from_slug(trip_slug)
        @photo = @trip.photos_dataset.where(id: photo_id).first || @trip.photos_dataset.where(legacy_photo_id: photo_id).first
        not_found unless @photo
        @title = "#{@trip.name} photo"
        view("photos/show")
      end

      r.get String do |trip_slug|
        @trip = trip_from_slug(trip_slug)
        @account = @trip.account
        @photos = @trip.photos_dataset.order(:taken_at, :id).all
        @comments = @trip.comments_dataset.order(:created_at, :id).all
        @hearts = @trip.hearts_dataset.all
        @title = @trip.name
        view("hikes/show")
      end

      r.get do
        @trips = WentHiking::Models::Trip.reverse_order(:hiked_at).limit(50).all
        @title = "Recent Hikes"
        view("hikes/index")
      end
    end

    r.on "users", Integer, "hikes" do |legacy_user_id|
      account = WentHiking::Models::Account.where(legacy_user_id: legacy_user_id).first || WentHiking::Models::Account[legacy_user_id]
      not_found unless account

      r.get Integer do |legacy_trip_id|
        trip = account.trips_dataset.where(legacy_trip_id: legacy_trip_id).first || WentHiking::Models::Trip.where(legacy_trip_id: legacy_trip_id).first
        not_found unless trip
        redirect trip.public_path
      end

      r.get do
        redirect account.public_path
      end
    end

    r.on "with" do
      r.get true do
        redirect "/people/#{r.remaining_path.to_s.sub(%r{\A/+}, "")}"
      end
    end
  end

  private

  def trip_from_slug(value)
    id = WentHiking::Slug.extract_id(value)
    trip = WentHiking::Models::Trip[id] || WentHiking::Models::Trip.where(legacy_trip_id: id).first
    not_found unless trip
    trip
  end
end
