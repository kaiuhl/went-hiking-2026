# frozen_string_literal: true

require "date"

module PageRoutes
  RETIRED_FEATURES = {
    "forecasts" => ["Forecasts are retired.", "The old weather integration rotted and is intentionally not part of V2."],
    "map_layers" => ["Map layers are retired.", "Trip maps remain, but route drawing, GPX layers, and old map-layer uploads are not part of V2."],
    "messages" => ["Messages are retired.", "Private messages were not durable trip content and are excluded from the rebuilt site."],
    "notifications" => ["Notifications are retired.", "Legacy notifications are not being carried forward."],
    "photos" => ["Global photo browsing is retired.", "Photos now live with their trip reports."],
    "routes" => ["Route drawing is retired.", "The old route drawing tools are intentionally not part of V2."]
  }.freeze

  def route_pages(r)
    r.root do
      @recent_trips = WentHiking::Models::Trip.reverse_order(:hiked_at).limit(12).all
      @map_points = WentHiking::Models::Trip
        .exclude(lat: nil)
        .exclude(lng: nil)
        .reverse_order(:hiked_at)
        .limit(100)
        .all
      @archive_stats = archive_stats
      @leaderboards = leaderboards_for(Date.today.year)
      @newest_members = WentHiking::Models::Account.reverse_order(:created_at).limit(8).all
      @title = "Went Hiking"
      view("pages/home")
    end

    r.get "about" do
      @title = "About"
      view("pages/about")
    end

    r.get "privacy_policy" do
      redirect "/privacy"
    end

    r.get "privacy" do
      @title = "Privacy"
      view("pages/privacy")
    end

    r.get "donate" do
      redirect "/about"
    end

    r.get "advanced_search" do
      redirect "/search"
    end

    r.get "search" do
      @query = request.params["q"].to_s.strip
      @trips = search_trips(@query)
      @title = @query.empty? ? "Search Hikes" : "Search: #{@query}"
      @kicker = "Search"
      @heading = @query.empty? ? "Search Hikes" : "Search Results"
      view("hikes/index")
    end

    r.get "map" do
      response.status = 410
      @title = "Map Removed"
      retired_feature("map", title: "The old map is gone.", body: "The original global map no longer worked and is intentionally not part of V2. Trip maps still appear on trip and profile pages.")
    end

    RETIRED_FEATURES.each_key do |feature|
      r.on feature do
        retired_feature(feature)
      end
    end

    r.on "users", Integer do
      RETIRED_FEATURES.each_key do |feature|
        r.on feature do
          retired_feature(feature)
        end
      end
    end
  end

  private

  def search_trips(query)
    dataset = WentHiking::Models::Trip.reverse_order(:hiked_at)
    return dataset.limit(50).all if query.empty?

    pattern = "%#{query.downcase}%"
    dataset
      .where(Sequel.lit("LOWER(name) LIKE ? OR LOWER(COALESCE(report_markdown, '')) LIKE ?", pattern, pattern))
      .limit(50)
      .all
  end

  def archive_stats
    trips = WentHiking::Models::Trip.all
    {
      trips: trips.size,
      photos: WentHiking::Models::Photo.count,
      miles: trips.sum { |trip| trip.mileage.to_f },
      nights: trips.sum { |trip| trip.nights.to_i }
    }
  end

  def leaderboards_for(year)
    start_at = Time.local(year, 1, 1)
    end_at = Time.local(year + 1, 1, 1)
    trips = WentHiking::Models::Trip
      .where { hiked_at >= start_at }
      .where { hiked_at < end_at }
      .all
    by_account = trips.group_by(&:account)

    {
      mileage: leaderboard(by_account) { |account_trips| account_trips.sum { |trip| trip.mileage.to_f } },
      elevation: leaderboard(by_account) { |account_trips| account_trips.sum { |trip| trip.elevation.to_i } },
      nights: leaderboard(by_account) { |account_trips| account_trips.sum { |trip| trip.nights.to_i } }
    }
  end

  def leaderboard(grouped_trips)
    grouped_trips.filter_map do |account, account_trips|
      value = yield(account_trips)
      next unless value.positive?

      {account: account, value: value}
    end.sort_by { |entry| -entry[:value] }.first(8)
  end

  def retired_feature(feature, title: nil, body: nil)
    default_title, default_body = RETIRED_FEATURES.fetch(feature, ["This feature is retired.", "This legacy feature is intentionally not part of V2."])
    response.status = 410
    @title = "Feature Retired"
    @retired_feature_title = title || default_title
    @retired_feature_body = body || default_body
    view("pages/gone")
  end
end
