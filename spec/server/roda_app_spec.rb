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

  it "returns gone for the unavailable global map" do
    get "/map"

    expect(last_response.status).to eq(410)
    expect(last_response.body).to include("big map is off trail")
  end

  it "returns gone for unavailable feature URLs" do
    get "/forecasts"
    expect(last_response.status).to eq(410)
    expect(last_response.body).to include("Forecasts are taking a break")

    get "/hikes/1-anything/comments"
    expect(last_response.status).to eq(410)
    expect(last_response.body).to include("New comments are taking a trail nap")
  end

  it "renders auth entry points" do
    get "/login"
    expect(last_response).to be_ok
    expect(last_response.body).to include("Email")

    get "/create-account"
    expect(last_response).to be_ok
    expect(last_response.body).to include("Create")
    expect(last_response.body).to include("Locale")
    expect(last_response.body).to include("A photo of you")
    expect(last_response.body).to include("Password")
  end

  it "creates public signup accounts pending verification and sends email" do
    WentHiking::Email.clear_deliveries
    fixture_path = File.join(WentHiking.root, "tmp/signup-avatar.jpg")
    FileUtils.mkdir_p(File.dirname(fixture_path))
    File.binwrite(fixture_path, "jpeg-ish".ljust(2048, "x"))

    post "/create-account", {
      "email" => "new@example.com",
      "name" => "New Hiker",
      "location" => "Portland, OR",
      "avatar" => Rack::Test::UploadedFile.new(fixture_path, "image/jpeg", true),
      "password" => "long-enough-password",
      "password-confirm" => "long-enough-password",
      "website" => ""
    }

    account = WentHiking.db[:accounts].where(email: "new@example.com").first
    expect(account).to include(name: "New Hiker", slug: "new-hiker", location: "Portland, OR", status_id: 1, avatar_file_name: "signup-avatar.jpg")
    expect(WentHiking.db[:account_password_hashes].where(id: account[:id]).count).to eq(1)
    expect(File.exist?(File.join(ENV.fetch("LOCAL_UPLOAD_ROOT"), "system/avatars/#{account[:id]}/medium/signup-avatar.jpg"))).to be(true)
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

  it "renders profile trip stats and navigation by year" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", location: "Portland, OR", status_id: 2, created_at: Time.now, updated_at: Time.now)
    WentHiking.db[:trips].insert(account_id: account_id, name: "Lookout Mountain", slug: "lookout-mountain", nights: 1, mileage: 12.0, elevation: 1700, hiked_at: Time.utc(2026, 7, 1), lat: 45.4, lng: -121.7, report_markdown: "Lovely day.", created_at: Time.now, updated_at: Time.now)
    WentHiking.db[:trips].insert(account_id: account_id, name: "Burnt Lake", slug: "burnt-lake", nights: 0, mileage: 8.5, elevation: 900, hiked_at: Time.utc(2025, 7, 1), lat: 45.6, lng: -121.9, report_markdown: "Lake day.", created_at: Time.now, updated_at: Time.now)

    get "/people/#{account_id}-kai"

    expect(last_response).to be_ok
    expect(last_response.body).to include("1 trip")
    expect(last_response.body).to include("12 miles logged")
    expect(last_response.body).to include("1 night out")
    expect(last_response.body).to include('<select id="profile-year"')
    expect(last_response.body).to include('<option value="2026" selected>2026</option>')
    expect(last_response.body).to include("Burnt Lake")
    expect(last_response.body).not_to include("2026 Trips")

    get "/people/#{account_id}-kai", {"year" => "2025"}

    expect(last_response).to be_ok
    expect(last_response.body).to include("Burnt Lake")
    expect(last_response.body).to include('<option value="2025" selected>2025</option>')
  end

  it "toggles hearts for authenticated hikers" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    trip_id = WentHiking.db[:trips].insert(account_id: account_id, name: "Burnt Lake", slug: "burnt-lake", nights: 1, hiked_at: Time.utc(2025, 7, 1), report_markdown: "Lovely day.", created_at: Time.now, updated_at: Time.now)
    trip = WentHiking::Models::Trip[trip_id]
    login_as(account_id)

    post "#{trip.public_path}/hearts", {"return_to" => trip.public_path}

    heart = WentHiking::Models::Heart.first(account_id: account_id, trip_id: trip_id)
    expect(last_response.status).to eq(302)
    expect(last_response.location).to include(trip.public_path)
    expect(heart.legacy_read_only).to be(false)

    get trip.public_path

    expect(last_response.body).to include('aria-pressed="true"')
    expect(last_response.body).to include("1 person has hearted this trip.")

    post "#{trip.public_path}/hearts", {"return_to" => trip.public_path}

    expect(last_response.status).to eq(302)
    expect(WentHiking::Models::Heart.where(account_id: account_id, trip_id: trip_id).count).to eq(0)
  end

  it "searches imported trip names and reports" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    WentHiking.db[:trips].insert(account_id: account_id, name: "Burnt Lake", slug: "burnt-lake", nights: 1, hiked_at: Time.utc(2025, 7, 1), report_markdown: "Lovely day.", created_at: Time.now, updated_at: Time.now)

    get "/search", {"q" => "burnt"}

    expect(last_response).to be_ok
    expect(last_response.body).to include("Search Results")
    expect(last_response.body).to include("Burnt Lake")
  end

  it "renders community totals and leaderboards on the home page" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    trip_id = WentHiking.db[:trips].insert(account_id: account_id, name: "Burnt Lake", slug: "burnt-lake", nights: 1, mileage: 8.5, elevation: 1700, hiked_at: Time.local(Date.today.year, 7, 1), lat: 45.4, lng: -121.7, report_markdown: "Lovely day.", created_at: Time.now, updated_at: Time.now)
    WentHiking.db[:trips].insert(account_id: account_id, name: "No Photo Ridge", slug: "no-photo-ridge", nights: 0, hiked_at: Time.local(Date.today.year, 6, 1), lat: 45.5, lng: -121.8, report_markdown: "Map-only day.", created_at: Time.now, updated_at: Time.now)
    first_photo_id = WentHiking.db[:photos].insert(account_id: account_id, trip_id: trip_id, legacy_photo_id: 321, legacy_image_file_name: "lake.jpg", caption: "Lake light", taken_at: Time.local(Date.today.year, 7, 1), created_at: Time.now, updated_at: Time.now)
    second_photo_id = WentHiking.db[:photos].insert(account_id: account_id, trip_id: trip_id, legacy_photo_id: 322, legacy_image_file_name: "ridge.jpg", caption: "Ridge light", taken_at: Time.local(Date.today.year, 7, 1, 13), created_at: Time.now, updated_at: Time.now)
    WentHiking.db[:photo_variants].insert(photo_id: first_photo_id, style: "large", filename: "lake.jpg", s3_key: "system/images/321/large/lake.jpg", created_at: Time.now, updated_at: Time.now)
    WentHiking.db[:photo_variants].insert(photo_id: second_photo_id, style: "large", filename: "ridge.jpg", s3_key: "system/images/322/large/ridge.jpg", created_at: Time.now, updated_at: Time.now)

    get "/"

    expect(last_response).to be_ok
    expect(last_response.body).to match(%r{<link rel="stylesheet" href="/styles/site\.css\?v=\d+">})
    expect(last_response.body).to include("8.5 miles logged")
    expect(last_response.body).to include("miles logged")
    expect(last_response.body).to include("Leaders")
    expect(last_response.body).to include("data-map-collection")
    expect(last_response.body).to include("data-photo-lightbox-gallery")
    expect(last_response.body).to include("2 photos")
    expect(last_response.body).to include("data-static-map")
  end

  it "renders the hike index with the shared hike list treatment" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    trip_id = WentHiking.db[:trips].insert(account_id: account_id, name: "Burnt Lake", slug: "burnt-lake", nights: 0, mileage: 8.5, elevation: 1700, hiked_at: Time.utc(2026, 7, 1), lat: 45.4, lng: -121.7, report_markdown: "Lovely day.", created_at: Time.now, updated_at: Time.now)
    WentHiking.db[:trips].insert(account_id: account_id, name: "Map Only Ridge", slug: "map-only-ridge", nights: 0, mileage: 3.2, hiked_at: Time.utc(2026, 6, 1), lat: 45.5, lng: -121.8, report_markdown: "Map-only day.", created_at: Time.now, updated_at: Time.now)
    5.times do |index|
      legacy_photo_id = 421 + index
      filename = "lake-#{index + 1}.jpg"
      photo_id = WentHiking.db[:photos].insert(account_id: account_id, trip_id: trip_id, legacy_photo_id: legacy_photo_id, legacy_image_file_name: filename, caption: "Lake light", taken_at: Time.utc(2026, 7, 1, 12 + index), created_at: Time.now, updated_at: Time.now)
      WentHiking.db[:photo_variants].insert(photo_id: photo_id, style: "large", filename: filename, s3_key: "system/images/#{legacy_photo_id}/large/#{filename}", created_at: Time.now, updated_at: Time.now)
    end

    get "/hikes"

    expect(last_response).to be_ok
    expect(last_response.body).to include("home-trip-list")
    expect(last_response.body).to include("home-trip-row")
    expect(last_response.body).to include("data-photo-lightbox-gallery")
    expect(last_response.body).to include("data-static-map")
    expect(last_response.body).to include("5 photos")
    expect(last_response.body).to include('data-photo-index="1"')
    expect(last_response.body).to include('data-photo-index="2"')
    expect(last_response.body).to include('data-photo-index="3"')
    expect(last_response.body).to include('data-photo-index="4"')
    expect(last_response.body).to include(">+1</a>")
    expect(last_response.body).to include("Showing 2")
  end

  it "renders the authenticated new hike form" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    login_as(account_id)

    get "/"
    expect(last_response.body).to include("Hi, Kai.")
    expect(last_response.body).to include('aria-label="Add a new hike"')
    expect(last_response.body).to include("Settings")
    expect(last_response.body).not_to include("New hike</a>")
    expect(last_response.body).not_to include("Account</a>")

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

  it "uploads photos for trips owned by the authenticated account" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    trip_id = WentHiking.db[:trips].insert(account_id: account_id, name: "Burnt Lake", slug: "burnt-lake", nights: 0, hiked_at: Time.utc(2026, 5, 1), created_at: Time.now, updated_at: Time.now)
    trip = WentHiking::Models::Trip[trip_id]
    fixture_path = File.join(WentHiking.root, "tmp/upload-photo.jpg")
    FileUtils.mkdir_p(File.dirname(fixture_path))
    File.binwrite(fixture_path, "jpeg-ish".ljust(2048, "x"))
    allow(WentHiking::PhotoMetadata).to receive(:extract).and_return(width: 1200, height: 800, camera_model: "Test Camera")
    allow(WentHiking::PhotoVariantJob).to receive(:enqueue_photo)
    login_as(account_id)

    post "#{trip.public_path}/photos", {
      "image" => Rack::Test::UploadedFile.new(fixture_path, "image/jpeg", true),
      "caption" => "Lake light"
    }

    photo = WentHiking::Models::Photo.first(caption: "Lake light")
    original = photo.variant("original")
    uploaded_path = File.join(ENV.fetch("LOCAL_UPLOAD_ROOT"), original.s3_key)

    expect(last_response.status).to eq(302)
    expect(photo.account_id).to eq(account_id)
    expect(photo.width).to eq(1200)
    expect(photo.camera_model).to eq("Test Camera")
    expect(original.s3_key).to eq("system/images/#{photo.id}/original/upload-photo.jpg")
    expect(File.exist?(uploaded_path)).to be(true)
    expect(WentHiking::PhotoVariantJob).to have_received(:enqueue_photo).with(photo.id)
  end

  it "renders the trip photo gallery" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    trip_id = WentHiking.db[:trips].insert(account_id: account_id, name: "Burnt Lake", slug: "burnt-lake", nights: 0, hiked_at: Time.utc(2026, 5, 1), created_at: Time.now, updated_at: Time.now)
    photo_id = WentHiking.db[:photos].insert(
      account_id: account_id,
      trip_id: trip_id,
      legacy_photo_id: 123,
      legacy_image_file_name: "lake.jpg",
      caption: "Lake light",
      taken_at: Time.utc(2026, 5, 1, 12, 30),
      camera_model: "Test Camera",
      camera_f_stop: "5.6",
      camera_exposure: "1/250",
      camera_iso: 200,
      created_at: Time.now,
      updated_at: Time.now
    )
    WentHiking.db[:photo_variants].insert(photo_id: photo_id, style: "large", filename: "lake.jpg", s3_key: "system/images/123/large/lake.jpg", created_at: Time.now, updated_at: Time.now)
    trip = WentHiking::Models::Trip[trip_id]

    get "#{trip.public_path}/photos"

    expect(last_response).to be_ok
    expect(last_response.body).to include("Photos from")
    expect(last_response.body).to include("Lake light")
    expect(last_response.body).to include("Test Camera")
    expect(last_response.body).to include("ISO 200")
  end

  it "halts cleanly for missing nested photo routes" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    trip_id = WentHiking.db[:trips].insert(account_id: account_id, name: "Burnt Lake", slug: "burnt-lake", nights: 0, hiked_at: Time.utc(2026, 5, 1), created_at: Time.now, updated_at: Time.now)
    trip = WentHiking::Models::Trip[trip_id]

    get "#{trip.public_path}/photos/9999"

    expect(last_response.status).to eq(404)
    expect(last_response.body).to include("No trail here")
  end

  it "updates account settings for the authenticated account" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    login_as(account_id)

    get "/account"
    expect(last_response).to be_ok
    expect(last_response.body).to include("Change password")

    post "/account", {"name" => "Kai Updated", "location" => "Portland, OR"}

    expect(last_response).to be_ok
    expect(WentHiking::Models::Account[account_id].name).to eq("Kai Updated")
    expect(WentHiking::Models::Account[account_id].location).to eq("Portland, OR")
  end

  it "redirects old hike ids to canonical paths" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    WentHiking.db[:trips].insert(account_id: account_id, legacy_trip_id: 99, name: "Burnt Lake", slug: "burnt-lake", nights: 0, hiked_at: Time.utc(2025, 7, 1), created_at: Time.now, updated_at: Time.now)

    get "/hikes/99"

    expect(last_response.status).to eq(302)
    expect(last_response.location).to include("/hikes/")
  end
end
