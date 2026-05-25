# frozen_string_literal: true

require "went_hiking/slug"
require "went_hiking/follow_subscription_request"

module PeopleRoutes
  def route_people(r)
    r.on "people" do
      r.post String, "follow" do |person_slug|
        @account = account_from_slug(person_slug)
        result = WentHiking::FollowSubscriptionRequest.new(
          account: @account,
          email: request.POST["email"],
          honeypot: request.POST["company"]
        ).call

        if result.success?
          redirect "#{@account.public_path}?follow=check-email"
        else
          setup_profile(@account)
          @follow_errors = result.errors
          @follow_email = request.POST["email"].to_s
          response.status = 422
          view("people/show")
        end
      end

      r.get String do |person_slug|
        setup_profile(account_from_slug(person_slug))
        @follow_notice = "Check your email to confirm this follow." if request.params["follow"] == "check-email"
        view("people/show")
      end
    end
  end

  private

  def setup_profile(account)
    @account = account
    @trip_years = trip_years(@account)
    requested_year = request.params["year"]&.to_i
    @year = @trip_years.include?(requested_year) ? requested_year : latest_trip_year(@account)
    @trips = @account.trips_dataset.published.where(Sequel.extract(:year, :hiked_at) => @year).reverse_order(:hiked_at).all
    @other_years = @trip_years - [@year]
    @title = @account.name
  end

  def account_from_slug(value)
    id = WentHiking::Slug.extract_id(value)
    account = WentHiking::Models::Account[id] || WentHiking::Models::Account.where(legacy_user_id: id).first
    not_found unless account
    account
  end

  def trip_years(account)
    account.trips_dataset.published.select_map { Sequel.extract(:year, :hiked_at) }.compact.map(&:to_i).uniq.sort.reverse
  rescue Sequel::DatabaseError
    account.trips.select(&:published?).map { |trip| trip.hiked_at&.year }.compact.uniq.sort.reverse
  end

  def latest_trip_year(account)
    trip_years(account).first || Time.now.year
  end
end
