# frozen_string_literal: true

require_relative "hikes"
require "went_hiking/pagination"
require "went_hiking/slug"
require "went_hiking/follow_subscription_request"

module PeopleRoutes
  MEMBERS_PER_PAGE = 40

  def route_people(r)
    r.on "people" do
      # Before this there was no index of members at all: a profile was
      # reachable from a trip byline or not at all, which left most hikers with
      # no inbound link anywhere on the site.
      r.get true do
        @accounts, @pagination = members_page(request.params["page"])
        @pager = {path: "/people", params: {}, label: "Member pages"}
        @title = "Hikers"
        @description = "The hikers of Went Hiking and the trips they have logged — profiles, mileage, and trip reports from the trail."
        view("people/index")
      end

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
        account = account_from_slug(person_slug)
        redirect_unless_canonical(account.public_path)
        setup_profile(account)
        @follow_notice = "Check your email to confirm this follow." if request.params["follow"] == "check-email"
        view("people/show")
      end
    end
  end

  private

  # The map used to plot every published trip this account ever logged — four
  # thousand markers and three quarters of a megabyte of attribute on the
  # heaviest profile, for a band a few hundred pixels tall. Home has always
  # shown its most recent hundred; profiles now do the same.
  PROFILE_MAP_LIMIT = 100

  def setup_profile(account)
    @account = account
    @trip_years = trip_years(@account)
    requested_year = request.params["year"]&.to_i
    # The year list is already in hand; asking the database for it a second time
    # to find the newest one is a scan of the account's whole archive for a
    # number sitting in a local variable.
    @year = @trip_years.include?(requested_year) ? requested_year : (@trip_years.first || Time.now.year)
    year_trips = @account.trips_dataset.published.in_year(@year)
    # The header counts the whole year, not the page of it being shown, so the
    # totals come from an aggregate rather than from summing the loaded rows.
    @year_totals = year_trips.totals
    @trips, @pagination = paginated_trip_list(year_trips, request.params["page"])
    @pager = {
      path: @account.public_path,
      params: {"year" => @year},
      label: "#{@account.name} #{@year} hike pages"
    }
    @profile_map_trips = @account.trips_dataset
      .published
      .exclude(lat: nil)
      .exclude(lng: nil)
      .reverse_order(:hiked_at, :id)
      .limit(PROFILE_MAP_LIMIT)
      .all
    @other_years = @trip_years - [@year]
    @profile_drafts = owned_drafts(@account)
    @title = @account.name
    from = @account.location.to_s.strip
    @description = [
      "Hikes by #{@account.name}#{" from #{from}" unless from.empty?} on Went Hiking:",
      "#{@year_totals[:trips]} #{(@year_totals[:trips] == 1) ? "trip" : "trips"} in #{@year},",
      "with trip reports, photos, and maps."
    ].join(" ")
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

  # Published trip counts come from one grouped aggregate joined to the page of
  # accounts, so the index costs two queries however many members there are.
  def members_page(page)
    counts = WentHiking::Models::Trip
      .published
      .group(:account_id)
      .select(:account_id) { count(:id).as(:trip_count) }
    trip_count = Sequel[:trip_counts][:trip_count]

    # Inner join, not left: a directory of hikers should list hikers. The
    # legacy archive carries accounts that never published a trip, and paging
    # through them would bury the people who did.
    pagination = WentHiking::Pagination.new(
      page: page,
      total: WentHiking::Models::Trip.published.select(:account_id).distinct.from_self.count,
      per_page: MEMBERS_PER_PAGE
    )
    accounts = WentHiking::Models::Account
      .join(counts.from_self.as(:trip_counts), account_id: :id)
      .select_all(:accounts)
      .select_append(Sequel.as(trip_count, :trip_count))
      .order(Sequel.desc(trip_count), Sequel[:accounts][:name], Sequel[:accounts][:id])
      .limit(pagination.per_page, pagination.offset)
      .all

    [accounts, pagination]
  end

  def account_from_slug(value)
    id = WentHiking::Slug.extract_id(value)
    account = WentHiking::Models::Account[id] || WentHiking::Models::Account.where(legacy_user_id: id).first
    not_found unless account
    account
  end

  # DISTINCT rather than one row per trip: this used to drag every one of an
  # account's several thousand hiked_at values across the wire to keep sixteen
  # of them.
  def trip_years(account)
    account.trips_dataset.published.distinct.select_map { Sequel.extract(:year, :hiked_at) }.compact.map(&:to_i).sort.reverse
  rescue Sequel::DatabaseError
    account.trips.select(&:published?).map { |trip| trip.hiked_at&.year }.compact.uniq.sort.reverse
  end
end
