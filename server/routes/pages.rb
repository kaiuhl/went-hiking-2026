# frozen_string_literal: true

require "date"

module PageRoutes
  RETIRED_FEATURES = {
    "forecasts" => ["Forecasts are taking a break.", "Trip pages are focused on where people went and what they found. Check your favorite weather source before heading out."],
    "map_layers" => ["Custom map layers are off the route.", "Trip maps are still here, but GPX layers and route drawing are sitting out while the new site gets faster and friendlier."],
    "messages" => ["Messages are off the pack list.", "Went Hiking is leaning into public trip sharing first: hikes, photos, maps, and comments people can discover."],
    "notifications" => ["Notifications are paused.", "For now, keep an eye on the hikes and people you like directly."],
    "photos" => ["Photos live with their hikes now.", "Open a hike to see its gallery, captions, camera details, and the story around the shots."],
    "routes" => ["Route drawing is back at basecamp.", "Maps still make trip pages shine; drawing tools can return later if they earn their pack weight."]
  }.freeze

  def route_pages(r)
    r.root do
      @recent_trips = WentHiking::Models::Trip.published.reverse_order(:hiked_at).limit(12).all
      @map_points = WentHiking::Models::Trip
        .published
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
      @title = "Map Trail Closed"
      retired_feature("map", title: "The big map is off trail for now.", body: "Trip and profile maps are still alive. The all-site map needs a better comeback than a quick patch, so it is sitting out this round.")
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
    dataset = WentHiking::Models::Trip.published.reverse_order(:hiked_at)
    return dataset.limit(50).all if query.empty?

    pattern = "%#{query.downcase}%"
    dataset
      .where(Sequel.lit("LOWER(name) LIKE ? OR LOWER(COALESCE(report_markdown, '')) LIKE ?", pattern, pattern))
      .limit(50)
      .all
  end

  def archive_stats
    trips = WentHiking::Models::Trip.published.all
    {
      trips: trips.size,
      photos: WentHiking::Models::Photo.join(:trips, id: :trip_id).where(Sequel[:trips][:status] => "published").count,
      miles: trips.sum { |trip| trip.mileage.to_f },
      nights: trips.sum { |trip| trip.nights.to_i }
    }
  end

  def leaderboards_for(year)
    start_at = Time.local(year, 1, 1)
    end_at = Time.local(year + 1, 1, 1)
    trips = WentHiking::Models::Trip
      .published
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
    default_title, default_body = RETIRED_FEATURES.fetch(feature, ["This trail is closed for now.", "We simplified this corner of Went Hiking so hikes, photos, maps, and stories can move faster."])
    response.status = 410
    @title = "Trail Closed"
    @retired_feature_title = title || default_title
    @retired_feature_body = body || default_body
    view("pages/gone")
  end
end
