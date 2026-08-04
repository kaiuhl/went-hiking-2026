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
