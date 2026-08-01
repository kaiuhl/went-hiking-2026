# frozen_string_literal: true

require_relative "hikes"
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
    @profile_drafts = owned_drafts(@account)
    @title = @account.name
  end

  # A draft is half a thought, and half a thought is not publishing: the list
  # exists only for the hiker whose profile this is. Everyone else — signed in,
  # signed out, or the neighbouring account — gets the same page they always got.
  def owned_drafts(account)
    viewer = current_account
    return [] unless viewer && viewer.id == account.id

    account.trips_dataset
      .drafts
      .reverse_order(:updated_at, :id)
      .all
      .reject { |trip| scratch_draft?(trip) }
  end

  # The compose page mints a draft the moment it opens, so one untouched
  # "Untitled Hike" is the residue of looking rather than a hike anyone
  # abandoned. Those are already reused and swept; listing them would only put a
  # phantom on the profile of everyone who ever clicked New Hike.
  def scratch_draft?(trip)
    trip.name.to_s == HikeRoutes::DRAFT_NAME &&
      trip.report_markdown.to_s.strip.empty? &&
      trip.photos_dataset.empty?
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
