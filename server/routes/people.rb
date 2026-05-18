# frozen_string_literal: true

require "went_hiking/slug"

module PeopleRoutes
  def route_people(r)
    r.on "people" do
      r.get String do |person_slug|
        @account = account_from_slug(person_slug)
        @year = (request.params["year"] || latest_trip_year(@account)).to_i
        @trips = @account.trips_dataset.where(Sequel.lit("EXTRACT(YEAR FROM hiked_at) = ?", @year)).reverse_order(:hiked_at).all
        @other_years = trip_years(@account) - [@year]
        @title = @account.name
        view("people/show")
      end
    end
  end

  private

  def account_from_slug(value)
    id = WentHiking::Slug.extract_id(value)
    account = WentHiking::Models::Account[id] || WentHiking::Models::Account.where(legacy_user_id: id).first
    not_found unless account
    account
  end

  def trip_years(account)
    account.trips_dataset.select_map { Sequel.extract(:year, :hiked_at) }.compact.map(&:to_i).uniq.sort.reverse
  rescue Sequel::DatabaseError
    account.trips.map { |trip| trip.hiked_at&.year }.compact.uniq.sort.reverse
  end

  def latest_trip_year(account)
    trip_years(account).first || Time.now.year
  end
end
