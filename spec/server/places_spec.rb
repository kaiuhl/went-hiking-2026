# frozen_string_literal: true

require_relative "../spec_helper"
require_relative "../../server/roda_app"

require "bcrypt"

RSpec.describe "Place search and hike locations" do
  include Rack::Test::Methods
  include CsrfHelpers

  def app
    RodaApp.app
  end

  def login_as(account_id, password: "long-enough-password")
    WentHiking.db[:account_password_hashes].insert(id: account_id, password_hash: BCrypt::Password.create(password).to_s)
    post "/login", {"email" => WentHiking.db[:accounts].where(id: account_id).get(:email), "password" => password}
    expect(last_response.status).to eq(302)
  end

  def create_account(name:)
    WentHiking.db[:accounts].insert(
      email: "#{name.downcase.gsub(/\W+/, "-")}@example.com",
      name: name,
      slug: name.downcase.gsub(/\W+/, "-"),
      status_id: 2,
      created_at: Time.now,
      updated_at: Time.now
    )
  end

  def create_place(name:, place_type: "lake", lat: 45.36, lng: -121.79, rank: 60, area: nil)
    dataset_id = WentHiking.db[:place_datasets].where(slug: "spec-dataset").get(:id) ||
      WentHiking.db[:place_datasets].insert(slug: "spec-dataset", name: "Spec", license_name: "Public Domain")
    place_id = WentHiking.db[:places].insert(
      slug: "spec-#{name.downcase.gsub(/\W+/, "-")}",
      name: name,
      place_type: place_type,
      latitude: lat,
      longitude: lng,
      state_code: "or",
      search_rank: rank,
      source_dataset_id: dataset_id
    )
    WentHiking.db[:place_names].insert(
      place_id: place_id,
      name: name,
      normalized_name: WentHiking::Places::Normalizer.normalize(name),
      kind: "official",
      weight: 100
    )
    if area
      area_id = WentHiking.db[:areas].where(slug: area).get(:id) || WentHiking.db[:areas].insert(
        slug: area,
        name: area.split("-").map(&:capitalize).join(" "),
        area_type: "wilderness",
        agency: "USFS"
      )
      WentHiking.db[:place_area_matches].insert(
        place_id: place_id, area_id: area_id,
        relationship: "contains_point", match_method: "rgeo_v1", confidence: 0.98
      )
    end
    place_id
  end

  def create_trip(account_id:, name:, status: "draft", **columns)
    WentHiking.db[:trips].insert(
      account_id: account_id,
      name: name,
      slug: name.downcase.gsub(/\W+/, "-"),
      nights: 0,
      hiked_at: Time.utc(2026, 7, 4),
      status: status,
      created_at: Time.now,
      updated_at: Time.now,
      **columns
    )
  end

  describe "GET /api/places/search" do
    it "returns scored matches with ids, subtitles, and a noindex header" do
      create_place(name: "Burnt Lake", area: "mount-hood-wilderness")

      get "/api/places/search", {"q" => "burnt lake"}

      expect(last_response.status).to eq(200)
      expect(last_response.headers["X-Robots-Tag"]).to eq("noindex")
      payload = JSON.parse(last_response.body)
      expect(payload["results"].length).to eq(1)
      result = payload["results"].first
      expect(result["name"]).to eq("Burnt Lake")
      expect(result["id"]).to be_a(Integer)
      expect(result["subtitle"]).to eq("Lake · Mount Hood Wilderness · Oregon")
      expect(result["lat"]).to eq(45.36)
    end

    it "answers nothing for short queries and clamps the limit" do
      create_place(name: "Burnt Lake")

      get "/api/places/search", {"q" => "b"}
      expect(JSON.parse(last_response.body)["results"]).to eq([])

      get "/api/places/search", {"q" => "burnt", "limit" => "999"}
      expect(last_response.status).to eq(200)

      get "/api/places/search", {"q" => "burnt", "limit" => "nope"}
      expect(last_response.status).to eq(200)
    end
  end

  describe "autosaving a chosen place" do
    it "snapshots the name and area server-side and stamps the author" do
      place_id = create_place(name: "Burnt Lake", area: "mount-hood-wilderness")
      account_id = create_account(name: "Kai")
      trip_id = create_trip(account_id: account_id, name: "Burnt Lake loop")
      login_as(account_id)

      post "/hikes/#{trip_id}-burnt-lake-loop/autosave", {"lat" => "45.36", "lng" => "-121.79", "place_id" => place_id.to_s}

      expect(last_response.status).to eq(200)
      trip = WentHiking.db[:trips].where(id: trip_id).first
      expect(trip[:place_id]).to eq(place_id)
      expect(trip[:location_name]).to eq("Burnt Lake")
      expect(trip[:area_name]).to eq("Mount Hood Wilderness")
      expect(trip[:location_source]).to eq("author")
      expect(trip[:location_resolved_at]).not_to be_nil
    end

    it "treats an unchanged place as a no-op, protecting backfilled words" do
      place_id = create_place(name: "Burnt Lake")
      account_id = create_account(name: "Kai")
      trip_id = create_trip(
        account_id: account_id, name: "Old hike",
        place_id: place_id, location_name: "Backfilled Name", area_name: "Backfilled Area", location_source: "auto_v1"
      )
      login_as(account_id)

      post "/hikes/#{trip_id}-old-hike/autosave", {"lat" => "45.36", "lng" => "-121.79", "place_id" => place_id.to_s}

      trip = WentHiking.db[:trips].where(id: trip_id).first
      expect(trip[:location_name]).to eq("Backfilled Name")
      expect(trip[:location_source]).to eq("auto_v1")
    end

    it "clears every location column when the author clears the place or the pin" do
      place_id = create_place(name: "Burnt Lake")
      account_id = create_account(name: "Kai")
      trip_id = create_trip(
        account_id: account_id, name: "Named hike",
        lat: 45.36, lng: -121.79,
        place_id: place_id, location_name: "Burnt Lake", location_source: "author"
      )
      login_as(account_id)

      post "/hikes/#{trip_id}-named-hike/autosave", {"lat" => "45.36", "lng" => "-121.79", "place_id" => ""}

      trip = WentHiking.db[:trips].where(id: trip_id).first
      expect(trip[:place_id]).to be_nil
      expect(trip[:location_name]).to be_nil
      expect(trip[:location_source]).to eq("author")

      # A backfilled name with no linked place still clears with the pin.
      WentHiking.db[:trips].where(id: trip_id).update(location_name: "Auto Name", location_source: "auto_v1")
      post "/hikes/#{trip_id}-named-hike/autosave", {"lat" => "", "lng" => "", "place_id" => ""}
      expect(WentHiking.db[:trips].where(id: trip_id).get(:location_name)).to be_nil
    end

    it "rejects a place that is no longer in the gazetteer" do
      account_id = create_account(name: "Kai")
      trip_id = create_trip(account_id: account_id, name: "Ghost hike")
      login_as(account_id)

      post "/hikes/#{trip_id}-ghost-hike/autosave", {"place_id" => "999999"}

      expect(last_response.status).to eq(422)
      expect(JSON.parse(last_response.body)["errors"]["location"]).to include("gazetteer")
      expect(WentHiking.db[:trips].where(id: trip_id).get(:place_id)).to be_nil
    end
  end

  describe "GET /search with places" do
    it "shows a Places strip on page one only, above intact text results" do
      create_place(name: "Goat Lake", area: "goat-rocks-wilderness")
      account_id = create_account(name: "Kai")
      create_trip(account_id: account_id, name: "Goat Lake scramble", status: "published")

      get "/search", {"q" => "goat lake"}
      expect(last_response.body).to include(">Places<")
      expect(last_response.body).to include("/places/spec-goat-lake")
      expect(last_response.body).to include("Goat Lake scramble")

      get "/search", {"q" => "goat lake", "page" => "2"}
      expect(last_response.body).not_to include(">Places<")
    end

    it "finds hikes by their backfilled location words" do
      account_id = create_account(name: "Kai")
      create_trip(
        account_id: account_id, name: "A quiet day out", status: "published",
        location_name: "Goat Lake", area_name: "Goat Rocks Wilderness"
      )

      get "/search", {"q" => "goat rocks"}
      expect(last_response.body).to include("A quiet day out")
    end
  end

  describe "GET /places/:slug" do
    it "lists hikes near a place by link or proximity, with a map" do
      place_id = create_place(name: "Burnt Lake", lat: 45.36, lng: -121.79)
      account_id = create_account(name: "Kai")
      create_trip(account_id: account_id, name: "Linked hike", status: "published", place_id: place_id)
      create_trip(account_id: account_id, name: "Nearby hike", status: "published", lat: 45.40, lng: -121.80)
      create_trip(account_id: account_id, name: "Far hike", status: "published", lat: 46.85, lng: -121.76)
      create_trip(account_id: account_id, name: "Hidden draft", status: "draft", place_id: place_id)

      get "/places/spec-burnt-lake"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Burnt Lake")
      expect(last_response.body).to include("Linked hike")
      expect(last_response.body).to include("Nearby hike")
      expect(last_response.body).not_to include("Far hike")
      expect(last_response.body).not_to include("Hidden draft")
      expect(last_response.body).to include("data-map")
    end

    it "serves area pages from the same namespace via area membership" do
      create_place(name: "Goat Lake", area: "goat-rocks-wilderness")
      area_id = WentHiking.db[:areas].where(slug: "goat-rocks-wilderness").get(:id)
      account_id = create_account(name: "Kai")
      create_trip(account_id: account_id, name: "Wilderness loop", status: "published", area_id: area_id)
      create_trip(account_id: account_id, name: "Elsewhere", status: "published")

      get "/places/goat-rocks-wilderness"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Wilderness loop")
      expect(last_response.body).not_to include("Elsewhere")
    end

    it "404s for unknown slugs" do
      get "/places/nowhere-at-all"
      expect(last_response.status).to eq(404)
    end
  end

  describe "publishing requires a place" do
    it "refuses new and draft publishes without a pin, but grandfathers old hikes" do
      account_id = create_account(name: "Kai")
      login_as(account_id)

      post "/hikes", {"name" => "Pinless", "hiked_at" => "2026-07-04", "nights" => "0"}
      expect(last_response.status).to eq(422)
      expect(last_response.body).to include("Every hike needs a place")

      draft_id = create_trip(account_id: account_id, name: "Pin free draft", status: "draft")
      post "/hikes/#{draft_id}-pin-free-draft", {"name" => "Pin free draft", "hiked_at" => "2026-07-04", "nights" => "0"}
      expect(last_response.status).to eq(422)

      post "/hikes", {"name" => "Pinned", "hiked_at" => "2026-07-04", "nights" => "0", "lat" => "45.36", "lng" => "-121.79"}
      expect(last_response.status).to eq(302)

      # A hike published before the rule keeps saving edits without one.
      old_id = create_trip(account_id: account_id, name: "Legacy hike", status: "published")
      post "/hikes/#{old_id}-legacy-hike", {"name" => "Legacy hike renamed", "hiked_at" => "2026-07-04", "nights" => "0"}
      expect(last_response.status).to eq(302)
    end
  end

  describe "bylines" do
    it "shows the location name on the hike page and in listings" do
      account_id = create_account(name: "Kai")
      create_trip(
        account_id: account_id, name: "Burnt Lake loop", status: "published",
        lat: 45.36, lng: -121.79, location_name: "Burnt Lake", area_name: "Mount Hood Wilderness"
      )

      get "/hikes/1-burnt-lake-loop"
      expect(last_response.body).to include("Burnt Lake")

      get "/hikes"
      expect(last_response.body).to include("<span>Burnt Lake</span>")
    end

    it "falls back to the containing area and stays silent without either" do
      account_id = create_account(name: "Kai")
      create_trip(
        account_id: account_id, name: "Somewhere wild", status: "published",
        lat: 46.5, lng: -121.4, area_name: "Goat Rocks Wilderness"
      )
      create_trip(account_id: account_id, name: "Nowhere named", status: "published")

      get "/hikes"
      expect(last_response.body).to include("<span>Goat Rocks Wilderness</span>")

      get "/hikes/2-nowhere-named"
      expect(last_response.status).to eq(200)
    end
  end
end
