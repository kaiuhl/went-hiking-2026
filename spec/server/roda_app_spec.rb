require_relative "../spec_helper"
require_relative "../../server/roda_app"

require "bcrypt"

RSpec.describe RodaApp do
  include Rack::Test::Methods

  def app
    described_class.app
  end

  def login_as(account_id, password: "long-enough-password")
    WentHiking.db[:account_password_hashes].insert(id: account_id, password_hash: BCrypt::Password.create(password).to_s)
    post "/login", {"email" => WentHiking.db[:accounts].where(id: account_id).get(:email), "password" => password}
    expect(last_response.status).to eq(302)
  end

  it "responds to health checks" do
    get "/health"

    expect(last_response).to be_ok
    expect(JSON.parse(last_response.body)).to eq("status" => "ok")
  end

  it "responds to version checks" do
    get "/api/version"

    expect(last_response).to be_ok
    expect(JSON.parse(last_response.body)).to include("app" => "went-hiking", "env" => "test")
  end

  it "renders markdown previews through the API" do
    post "/api/markdown-preview", {"body" => "Lovely **day** <script>alert(1)</script>"}

    expect(last_response).to be_ok
    expect(JSON.parse(last_response.body)["html"]).to include("<strong>day</strong>")
    expect(JSON.parse(last_response.body)["html"]).not_to include("<script>")
  end

  it "redirects legacy system media to the configured media base" do
    get "/system/images/32585/large/image.jpg"

    expect(last_response.status).to eq(302)
    expect(last_response.location).to eq("https://media.example.test/system/images/32585/large/image.jpg")
  end

  it "returns gone for the retired global map" do
    get "/map"

    expect(last_response.status).to eq(410)
    expect(last_response.body).to include("old map is gone")
  end

  it "renders auth entry points" do
    get "/login"
    expect(last_response).to be_ok
    expect(last_response.body).to include("Email")

    get "/create-account"
    expect(last_response).to be_ok
    expect(last_response.body).to include("Create")
  end

  it "creates public signup accounts pending verification and sends email" do
    WentHiking::Email.clear_deliveries

    post "/create-account", {
      "email" => "new@example.com",
      "name" => "New Hiker",
      "password" => "long-enough-password",
      "password-confirm" => "long-enough-password",
      "website" => ""
    }

    account = WentHiking.db[:accounts].where(email: "new@example.com").first
    expect(account).to include(name: "New Hiker", slug: "new-hiker", status_id: 1)
    expect(WentHiking::Email.deliveries.size).to eq(1)
  end

  it "renders imported trip pages" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    trip_id = WentHiking.db[:trips].insert(account_id: account_id, legacy_trip_id: 99, name: "Burnt Lake", slug: "burnt-lake", nights: 1, mileage: 8.5, elevation: 1700, hiked_at: Time.utc(2025, 7, 1), report_markdown: "Lovely **day**.", created_at: Time.now, updated_at: Time.now)

    get "/hikes/#{trip_id}-burnt-lake"

    expect(last_response).to be_ok
    expect(last_response.body).to include("Burnt Lake")
    expect(last_response.body).to include("<strong>day</strong>")
  end

  it "renders the authenticated new hike form" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    login_as(account_id)

    get "/hikes/new"

    expect(last_response).to be_ok
    expect(last_response.body).to include("New Hike")
    expect(last_response.body).to include("data-markdown-editor")
  end

  it "creates trips for the authenticated account" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    login_as(account_id)

    post "/hikes", {
      "name" => "Lookout Mountain",
      "hiked_at" => "2026-05-17",
      "nights" => "1",
      "mileage" => "8.5",
      "elevation" => "1700",
      "source_url" => "https://example.com/lookout",
      "lat" => "45.4",
      "lng" => "-121.7",
      "report_markdown" => "Clear views."
    }

    trip = WentHiking::Models::Trip.first(name: "Lookout Mountain")
    expect(trip.account_id).to eq(account_id)
    expect(trip.slug).to eq("lookout-mountain")
    expect(last_response.status).to eq(302)
    expect(last_response.location).to include(trip.public_path)
  end

  it "rerenders invalid trip submissions with errors" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    login_as(account_id)

    post "/hikes", {"name" => "", "hiked_at" => "not-a-date"}

    expect(last_response.status).to eq(422)
    expect(last_response.body).to include("Name is required.")
    expect(last_response.body).to include("Hike date must be a valid date.")
  end

  it "updates trips owned by the authenticated account" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    trip_id = WentHiking.db[:trips].insert(account_id: account_id, name: "Old Name", slug: "old-name", nights: 0, hiked_at: Time.utc(2026, 5, 1), created_at: Time.now, updated_at: Time.now)
    trip = WentHiking::Models::Trip[trip_id]
    login_as(account_id)

    post trip.public_path, {
      "name" => "New Name",
      "hiked_at" => "2026-05-02",
      "nights" => "0",
      "mileage" => "7",
      "elevation" => "900",
      "report_markdown" => "Updated."
    }

    expect(last_response.status).to eq(302)
    expect(trip.refresh.name).to eq("New Name")
    expect(trip.report_markdown).to eq("Updated.")
  end

  it "redirects old hike ids to canonical paths" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    WentHiking.db[:trips].insert(account_id: account_id, legacy_trip_id: 99, name: "Burnt Lake", slug: "burnt-lake", nights: 0, hiked_at: Time.utc(2025, 7, 1), created_at: Time.now, updated_at: Time.now)

    get "/hikes/99"

    expect(last_response.status).to eq(302)
    expect(last_response.location).to include("/hikes/")
  end
end
