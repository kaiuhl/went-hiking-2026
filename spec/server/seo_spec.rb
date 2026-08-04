# frozen_string_literal: true

require_relative "../spec_helper"
require_relative "../../server/roda_app"

RSpec.describe "SEO surface" do
  include Rack::Test::Methods

  def app
    RodaApp.app
  end

  def create_account(email: "kai@example.com", name: "Kai", slug: "kai")
    WentHiking.db[:accounts].insert(email: email, name: name, slug: slug, status_id: 2, created_at: Time.now, updated_at: Time.now)
  end

  def create_trip(account_id, name: "Burnt Lake", slug: "burnt-lake", **overrides)
    attributes = {
      account_id: account_id,
      name: name,
      slug: slug,
      nights: 0,
      hiked_at: Time.utc(2026, 5, 1),
      report_markdown: "A stroll up to the lake.",
      status: "published",
      published_at: Time.utc(2026, 5, 2),
      created_at: Time.now,
      updated_at: Time.now
    }.merge(overrides)

    WentHiking::Models::Trip[WentHiking.db[:trips].insert(attributes)]
  end

  describe "canonical slug redirects" do
    it "permanently redirects a stale hike slug to the canonical path" do
      trip = create_trip(create_account)

      get "/hikes/#{trip.id}-old-name"

      expect(last_response.status).to eq(301)
      expect(last_response.location).to end_with(trip.public_path)
    end

    it "permanently redirects a stale person slug, keeping the query string" do
      account_id = create_account
      account = WentHiking::Models::Account[account_id]

      get "/people/#{account_id}-somebody-else?year=2026"

      expect(last_response.status).to eq(301)
      expect(last_response.location).to end_with("#{account.public_path}?year=2026")
    end

    it "serves the canonical spelling without redirecting" do
      trip = create_trip(create_account)

      get trip.public_path

      expect(last_response.status).to eq(200)
    end
  end

  describe "titles and meta" do
    it "suffixes page titles with the site name" do
      get "/hikes"

      expect(last_response.body).to include("<title>Recent Hikes · Went Hiking</title>")
    end

    it "does not stutter the site name on the home page" do
      get "/"

      expect(last_response.body).to include("<title>Went Hiking — Hiking Trip Reports, Photos, and Maps</title>")
    end

    it "marks search results noindex" do
      get "/search", {"q" => "lake"}

      expect(last_response.body).to include(%(<meta name="robots" content="noindex">))
    end

    it "leaves hike pages indexable with article metadata" do
      trip = create_trip(create_account)

      get trip.public_path

      expect(last_response.body).not_to include(%(content="noindex"))
      expect(last_response.body).to include(%(property="article:published_time"))
      expect(last_response.body).to include(%(property="og:image:width"))
    end
  end

  describe "structured data" do
    it "marks a hike up as an Article at a Place" do
      trip = create_trip(create_account, lat: 45.3, lng: -121.7)

      get trip.public_path

      expect(last_response.body).to include(%(<script type="application/ld+json">))
      json = last_response.body[%r{<script type="application/ld\+json">(.*?)</script>}m, 1]
      data = JSON.parse(json)
      expect(data["@type"]).to eq("Article")
      expect(data["headline"]).to eq("Burnt Lake")
      expect(data["author"]).to include("name" => "Kai")
      expect(data["contentLocation"]["geo"]).to include("latitude" => 45.3, "longitude" => -121.7)
    end

    it "marks a profile up as a ProfilePage" do
      account = WentHiking::Models::Account[create_account]

      get account.public_path

      data = JSON.parse(last_response.body[%r{<script type="application/ld\+json">(.*?)</script>}m, 1])
      expect(data["@type"]).to eq("ProfilePage")
      expect(data["mainEntity"]).to include("name" => "Kai")
    end

    it "declares the site and its search action on the home page" do
      get "/"

      data = JSON.parse(last_response.body[%r{<script type="application/ld\+json">(.*?)</script>}m, 1])
      expect(data["@type"]).to eq("WebSite")
      expect(data.dig("potentialAction", "target", "urlTemplate")).to include("/search?q=")
    end
  end

  describe "canonical link tag" do
    it "keeps the page parameter so page two does not claim to be page one" do
      account_id = create_account
      30.times { |i| create_trip(account_id, name: "Hike #{i}", slug: "hike-#{i}") }

      get "/hikes", {"page" => "2"}

      expect(last_response.body).to include(%(<link rel="canonical" href="#{WentHiking.public_base_url}/hikes?page=2">))
    end

    it "drops stray query parameters from the canonical URL" do
      get "/hikes", {"utm_source" => "newsletter"}

      expect(last_response.body).to include(%(<link rel="canonical" href="#{WentHiking.public_base_url}/hikes">))
    end
  end
end
