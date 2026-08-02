require_relative "../spec_helper"
require_relative "../../server/roda_app"

require "bcrypt"

RSpec.describe RodaApp do
  include Rack::Test::Methods
  include CsrfHelpers

  def app
    described_class.app
  end

  def login_as(account_id, password: "long-enough-password")
    WentHiking.db[:account_password_hashes].insert(id: account_id, password_hash: BCrypt::Password.create(password).to_s)
    post "/login", {"email" => WentHiking.db[:accounts].where(id: account_id).get(:email), "password" => password}
    expect(last_response.status).to eq(302)
  end

  def make_real_jpeg(path)
    FileUtils.mkdir_p(File.dirname(path))
    Vips::Image.black(800, 600).jpegsave(path)
    path
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
    expect(last_response.body).to include("Welcome back!")
    expect(last_response.body).to include("reset your password")
    expect(last_response.body).to include("Went Hiking recently moved to new infrastructure")
    expect(last_response.body).to include('autofocus="autofocus"')

    get "/create-account"
    expect(last_response).to be_ok
    expect(last_response.body).to include("Create")
    # The field stores accounts.location and /account has always called it
    # Location; "Locale" was the odd one out.
    expect(last_response.body).to include("Location")
    expect(last_response.body).not_to include("Locale")
    expect(last_response.body).to include("A photo of you")
    expect(last_response.body).to include("Password")
    expect(last_response.body).not_to include('autofocus="autofocus"')
    # Name, then credentials, then the optional extras.
    expect(last_response.body.index('id="name"')).to be < last_response.body.index('id="login"')
    expect(last_response.body.index('id="password"')).to be < last_response.body.index('id="location"')
    expect(last_response.body.index('id="location"')).to be < last_response.body.index('id="avatar"')
  end

  it "renders a logout confirmation rather than a bare button" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    login_as(account_id)

    get "/logout"

    expect(last_response).to be_ok
    expect(last_response.body).to include("Log out?")
    expect(last_response.body).to include(">Log out</button>")
    expect(last_response.body).to include("Never mind")
  end

  it "keeps login primary when the password is wrong" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    WentHiking.db[:account_password_hashes].insert(id: account_id, password_hash: BCrypt::Password.create("long-enough-password").to_s)

    post "/login", {"email" => "kai@example.com", "password" => "wrong-password-entirely"}

    expect(last_response.status).to eq(401)
    # rodauth injects a whole reset-password form above the login form on
    # failure; the login view drops it in favour of the quiet link.
    expect(last_response.body).not_to include("reset-password-request-form")
    expect(last_response.body).to include('aria-invalid="true"')
    expect(last_response.body).to include('id="password_error_message"')
    expect(last_response.body).to include("Forgot your password?")
  end

  # Rodauth checks verification before it ever looks at the password, so this
  # page stands in for the login form and has to explain itself on its own.
  it "explains itself when an unverified account tries to log in" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 1, created_at: Time.now, updated_at: Time.now)
    WentHiking.db[:account_password_hashes].insert(id: account_id, password_hash: BCrypt::Password.create("long-enough-password").to_s)

    post "/login", {"email" => "kai@example.com", "password" => "long-enough-password"}

    expect(last_response.body).to include("<h1>Verify your account</h1>")
    expect(last_response.body).to include("still needs to be verified")
    expect(last_response.body).to include("kai@example.com")
    expect(last_response.body).to include("verify-account-resend-form")
    # The generic rodauth flash would only be the same sentence twice, and it is
    # set for a request this page never gets to.
    expect(last_response.body).not_to include("awaiting verification")
  end

  it "renders rodauth's flash messages rather than dropping them on the floor" do
    post "/create-account", {
      "email" => "flash@example.com",
      "name" => "Flash Hiker",
      "password" => "long-enough-password",
      "password-confirm" => "long-enough-password",
      "website" => ""
    }

    expect(last_response.status).to eq(302)
    follow_redirect!

    expect(last_response.body).to include('class="flash flash-notice" role="status"')
    expect(last_response.body).to include("verify your account")
  end

  it "renders a flash error with an alert role" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    WentHiking.db[:account_password_hashes].insert(id: account_id, password_hash: BCrypt::Password.create("long-enough-password").to_s)

    post "/login", {"email" => "kai@example.com", "password" => "wrong-password-entirely"}

    expect(last_response.body).to include('class="flash flash-error" role="alert"')
  end

  it "renders no flash region when there is nothing to say" do
    get "/about"

    expect(last_response).to be_ok
    expect(last_response.body).not_to include("flash-region")
  end

  it "answers a honeypot signup with a branded page rather than bare text" do
    post "/create-account", {
      "email" => "bot@example.com",
      "name" => "Bot",
      "password" => "long-enough-password",
      "password-confirm" => "long-enough-password",
      "website" => "http://spam.example"
    }

    expect(last_response.status).to eq(422)
    expect(last_response.headers["Content-Type"]).to include("text/html")
    expect(last_response.body).to include("That account could not be created.")
    expect(WentHiking.db[:accounts].where(email: "bot@example.com").count).to eq(0)
    expect(WentHiking.db[:signup_attempts].where(honeypot_filled: true).count).to eq(1)
  end

  it "gives every rodauth page a heading and a title" do
    %w[/login /create-account /reset-password-request /verify-account-resend].each do |path|
      get path

      expect(last_response.body).to match(/<h1[ >]/), "#{path} renders with no h1"
      expect(last_response.body).to match(%r{<title>.+</title>}), "#{path} renders with no title"
    end
  end

  it "opens every page with a skip link to the main landmark" do
    get "/about"

    expect(last_response.body).to include(%(<a class="skip-link" href="#main">Skip to content</a>))
    expect(last_response.body).to include(%(<main id="main" tabindex="-1">))
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
    expect(WentHiking::Email.deliveries.first.subject).to eq("Verify your Went Hiking account")
    expect(WentHiking::Email.deliveries.first.html_body).to include("Verify account")
  end

  it "queues branded password reset emails" do
    WentHiking::Email.clear_deliveries
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    WentHiking.db[:account_password_hashes].insert(id: account_id, password_hash: BCrypt::Password.create("long-enough-password").to_s)

    post "/reset-password-request", {"email" => "kai@example.com"}

    expect(last_response.status).to eq(302)
    expect(WentHiking::Email.deliveries.size).to eq(1)
    expect(WentHiking::Email.deliveries.first.subject).to eq("Reset your Went Hiking password")
    expect(WentHiking::Email.deliveries.first.text_body).to include("/reset-password")
    expect(WentHiking::Email.deliveries.first.html_body).to include("Reset password")
  end

  it "queues branded unlock account emails" do
    WentHiking::Email.clear_deliveries
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    WentHiking.db[:account_lockouts].insert(id: account_id, key: "unlock-key", deadline: Time.now + 3600, email_last_sent: Time.now - 600)

    post "/unlock-account-request", {"email" => "kai@example.com"}

    expect(last_response.status).to eq(302)
    expect(WentHiking::Email.deliveries.size).to eq(1)
    expect(WentHiking::Email.deliveries.first.subject).to eq("Unlock your Went Hiking account")
    expect(WentHiking::Email.deliveries.first.text_body).to include("/unlock-account")
    expect(WentHiking::Email.deliveries.first.html_body).to include("Unlock account")
  end

  it "renders imported trip pages" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    trip_id = WentHiking.db[:trips].insert(account_id: account_id, legacy_trip_id: 99, name: "Burnt Lake", slug: "burnt-lake", nights: 1, mileage: 8.5, elevation: 1700, hiked_at: Time.utc(2025, 7, 1), report_markdown: "Lovely **day**.", created_at: Time.now, updated_at: Time.now)

    get "/hikes/#{trip_id}-burnt-lake"

    expect(last_response).to be_ok
    expect(last_response.body).to include("Burnt Lake")
    expect(last_response.body).to include('class="trip-kicker-action"')
    expect(last_response.body).to include("<span>went backpacking</span>")
    expect(last_response.body).to include("<strong>day</strong>")
  end

  it "renders profile trip stats and navigation by year" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", location: "Portland, OR", status_id: 2, created_at: Time.now, updated_at: Time.now)
    trip_id = WentHiking.db[:trips].insert(account_id: account_id, name: "Lookout Mountain", slug: "lookout-mountain", nights: 1, mileage: 12.0, elevation: 1700, hiked_at: Time.utc(2026, 7, 1), lat: 45.4, lng: -121.7, report_markdown: "Lovely day.", created_at: Time.now, updated_at: Time.now)
    WentHiking.db[:trips].insert(account_id: account_id, name: "Burnt Lake", slug: "burnt-lake", nights: 0, mileage: 8.5, elevation: 900, hiked_at: Time.utc(2025, 7, 1), lat: 45.6, lng: -121.9, report_markdown: "Lake day.", created_at: Time.now, updated_at: Time.now)
    first_photo_id = WentHiking.db[:photos].insert(account_id: account_id, trip_id: trip_id, legacy_photo_id: 171, legacy_image_file_name: "lookout-1.jpg", caption: "Lookout light", taken_at: Time.utc(2026, 7, 1, 12), created_at: Time.now, updated_at: Time.now)
    second_photo_id = WentHiking.db[:photos].insert(account_id: account_id, trip_id: trip_id, legacy_photo_id: 172, legacy_image_file_name: "lookout-2.jpg", caption: "Trail light", taken_at: Time.utc(2026, 7, 1, 13), created_at: Time.now, updated_at: Time.now)
    WentHiking.db[:photo_variants].insert(photo_id: first_photo_id, style: "large", filename: "lookout-1.jpg", s3_key: "system/images/171/large/lookout-1.jpg", created_at: Time.now, updated_at: Time.now)
    WentHiking.db[:photo_variants].insert(photo_id: second_photo_id, style: "large", filename: "lookout-2.jpg", s3_key: "system/images/172/large/lookout-2.jpg", created_at: Time.now, updated_at: Time.now)

    get "/people/#{account_id}-kai"

    expect(last_response).to be_ok
    expect(last_response.body).to include("1 trip")
    expect(last_response.body).to include("12 miles logged")
    expect(last_response.body).to include("1 night out")
    expect(last_response.body).to include('<nav class="profile-years"')
    expect(last_response.body).to include(%(href="/people/#{account_id}-kai?year=2025"))
    expect(last_response.body).to include(%(class="profile-year is-current" href="/people/#{account_id}-kai?year=2026" aria-current="page">2026</a>))
    expect(last_response.body).to include("Burnt Lake")
    expect(last_response.body).to include('<div class="trip-list">')
    expect(last_response.body).to include('<article class="trip-row"')
    expect(last_response.body).to include("trip-row-content")
    expect(last_response.body).to include("trip-photo-gallery")
    expect(last_response.body).to include("trip-map-tile")
    expect(last_response.body).to include("data-photo-lightbox-gallery")
    expect(last_response.body).to include("Lovely day.")
    expect(last_response.body).to match(/trip-map-tile.*data-photo-index="0"/m)
    expect(last_response.body).not_to include("profile-trip-photo")
    expect(last_response.body).not_to include("<h2>Photos</h2>")
    expect(last_response.body).not_to include("2026 Trips")

    get "/people/#{account_id}-kai", {"year" => "2025"}

    expect(last_response).to be_ok
    expect(last_response.body).to include("Burnt Lake")
    expect(last_response.body).to include(%(class="profile-year is-current" href="/people/#{account_id}-kai?year=2025" aria-current="page">2025</a>))
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
    expect(last_response.body).to include('title="1 heart"')
    expect(last_response.body).to include('<span class="heart-count" data-heart-count>1</span>')
    # Hearts alone no longer conjure a Trail Talk section out of nothing.
    expect(last_response.body).not_to include("Trail Talk")

    post "#{trip.public_path}/hearts", {"return_to" => trip.public_path}

    expect(last_response.status).to eq(302)
    expect(WentHiking::Models::Heart.where(account_id: account_id, trip_id: trip_id).count).to eq(0)
  end

  # return_to is attacker-controlled, and a browser reads both "//evil.com" and
  # "/\evil.com" as somewhere else entirely.
  it "refuses to bounce a heart anywhere but back into the site" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    trip_id = WentHiking.db[:trips].insert(account_id: account_id, name: "Burnt Lake", slug: "burnt-lake", nights: 1, hiked_at: Time.utc(2025, 7, 1), report_markdown: "Lovely day.", created_at: Time.now, updated_at: Time.now)
    trip = WentHiking::Models::Trip[trip_id]
    login_as(account_id)

    ["//evil.com", "/\\evil.com", "/\\\\evil.com", "https://evil.com", "javascript:alert(1)"].each do |target|
      post "#{trip.public_path}/hearts", {"return_to" => target}

      expect(last_response.status).to eq(302)
      expect(last_response.location).to end_with(trip.public_path), "#{target} escaped the site"
    end

    post "#{trip.public_path}/hearts", {"return_to" => "/hikes?year=2025"}

    expect(last_response.location).to end_with("/hikes?year=2025")
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
    expect(last_response.body).to include("trip-photo-gallery")
    expect(last_response.body).to include("data-static-map")
    expect(last_response.body).to include("trip-map-tile")
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
    expect(last_response.body).to include('<div class="trip-list">')
    expect(last_response.body).to include('<article class="trip-row"')
    expect(last_response.body).to include("data-photo-lightbox-gallery")
    expect(last_response.body).to include("data-static-map")
    expect(last_response.body).to include("trip-photo-gallery")
    expect(last_response.body).to include("trip-map-tile")
    expect(last_response.body).to include("Lovely day.")
    expect(last_response.body).not_to include("<h2>Photos</h2>")
    expect(last_response.body).to match(/trip-map-tile.*data-photo-index="0"/m)
    expect(last_response.body).to include('data-photo-index="1"')
    expect(last_response.body).to include('data-photo-index="2"')
    expect(last_response.body).to include('data-photo-index="3"')
    expect(last_response.body).to include('data-photo-index="4"')
    # The count describes the whole archive now, not the slice on screen; it
    # used to read "Showing 50" whether fifty hikes existed or eight thousand.
    expect(last_response.body).to include("2 hikes")
  end

  it "renders the compose page for a new hike" do
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
    expect(last_response.body).to include('data-mode="new"')
    expect(last_response.body).to include('data-draft-url="/hikes/drafts"')
    expect(last_response.body).to include("data-compose-canvas")
    expect(last_response.body).to include("data-compose-byline")
    expect(last_response.body).to include("data-compose-tray")
    expect(last_response.body).to include('placeholder="Name this hike"')
    expect(last_response.body).to match(/data-compose-submit>\s*Publish\s*</)
    # The editor's assets are gated to the pages that need them.
    expect(last_response.body).to match(%r{<link rel="stylesheet" href="/styles/editor\.css\?v=\d+">})
    expect(last_response.body).to match(%r{<script src="/scripts/editor\.js\?v=\d+" defer></script>})
    # A new hike has nothing to delete or view yet, and nothing to autosave to.
    expect(last_response.body).to include('data-autosave-url=""')
    expect(last_response.body).not_to include("Untitled Hike")
  end

  it "renders the compose page for an existing hike with its photos and urls" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    trip_id = WentHiking.db[:trips].insert(account_id: account_id, name: "Burnt Lake", slug: "burnt-lake", nights: 1, mileage: 8.5, elevation: 1700, hiked_at: Time.utc(2026, 7, 1), lat: 45.4, lng: -121.7, report_markdown: "Lovely day.", created_at: Time.now, updated_at: Time.now)
    photo_id = WentHiking.db[:photos].insert(account_id: account_id, trip_id: trip_id, legacy_photo_id: 321, legacy_image_file_name: "lake.jpg", caption: "Lake light", taken_at: Time.utc(2026, 7, 1), created_at: Time.now, updated_at: Time.now)
    WentHiking.db[:photo_variants].insert(photo_id: photo_id, style: "large", filename: "lake.jpg", s3_key: "system/images/321/large/lake.jpg", created_at: Time.now, updated_at: Time.now)
    trip = WentHiking::Models::Trip[trip_id]
    login_as(account_id)

    get "#{trip.public_path}/edit"

    expect(last_response).to be_ok
    expect(last_response.body).to include('data-mode="published"')
    expect(last_response.body).to include(%(data-autosave-url="#{trip.public_path}/autosave"))
    expect(last_response.body).to include(%(data-upload-url="#{trip.public_path}/photos/direct-upload"))
    expect(last_response.body).to match(/data-compose-submit>\s*Save changes\s*</)
    expect(last_response.body).to include("Delete hike")
    # The story arrives as markdown and the photos as JSON; the editor builds
    # the canvas and the gallery tray from exactly these two.
    expect(last_response.body).to include("Lovely day.")
    expect(last_response.body).to include("data-compose-photos")
    expect(last_response.body).to include("Lake light")
    expect(last_response.body).to include(%(value="45.4"))
    expect(last_response.body).to include(%(value="-121.7"))
    # The photo JSON carries each photo's calendar day so the editor can date
    # a hike from its photos, and a published hike's date is never up for grabs.
    expect(last_response.body).to include(%("taken_on":"2026-07-01"))
    expect(last_response.body).to include('data-date-untouched="false"')
  end

  it "flags whether the hike date is still the draft default" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    login_as(account_id)

    get "/hikes/new"
    expect(last_response.body).to include('data-date-untouched="true"')

    post "/hikes/drafts"
    draft = WentHiking::Models::Trip[JSON.parse(last_response.body).fetch("trip_id")]

    # A fresh draft wears the day it was opened; the editor may re-date it.
    get "#{draft.public_path}/edit"
    expect(last_response.body).to include('data-date-untouched="true"')

    # Once the writer has picked a date, reopening the draft must not offer
    # the photos another turn.
    post "#{draft.public_path}/autosave", {"hiked_at" => "2026-05-17"}
    expect(last_response).to be_ok

    get "#{draft.public_path}/edit"
    expect(last_response.body).to include('data-date-untouched="false"')
  end

  it "pins compose errors to the control that caused them" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    login_as(account_id)

    post "/hikes", {"name" => "", "hiked_at" => "not-a-date", "mileage" => "eight"}

    expect(last_response.status).to eq(422)
    expect(last_response.body).to include('data-compose-error="name"')
    expect(last_response.body).to include('data-compose-error="hiked_at"')
    expect(last_response.body).to include('data-compose-error="mileage"')
  end

  it "sends the old photo upload page into the editor" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    trip_id = WentHiking.db[:trips].insert(account_id: account_id, name: "Burnt Lake", slug: "burnt-lake", nights: 0, hiked_at: Time.utc(2026, 7, 1), created_at: Time.now, updated_at: Time.now)
    trip = WentHiking::Models::Trip[trip_id]
    login_as(account_id)

    get "#{trip.public_path}/photos/new"

    expect(last_response.status).to eq(302)
    expect(last_response.location).to eq("#{trip.public_path}/edit")
  end

  it "creates private draft hikes for editor uploads" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    login_as(account_id)

    post "/hikes/drafts"

    payload = JSON.parse(last_response.body)
    draft = WentHiking::Models::Trip[payload.fetch("trip_id")]

    expect(last_response.status).to eq(201)
    expect(payload["edit_url"]).to eq("#{draft.public_path}/edit")
    expect(payload["upload_url"]).to eq("#{draft.public_path}/photos/direct-upload")
    expect(draft.status).to eq("draft")
    expect(draft.published_at).to be_nil

    get "/hikes"
    expect(last_response.body).not_to include("Untitled Hike")

    get draft.public_path
    expect(last_response.status).to eq(404)

    get "/search", {"q" => "Untitled"}
    expect(last_response.body).not_to include("Untitled Hike")

    get "/people/#{account_id}-kai"
    expect(last_response.body).not_to include("Untitled Hike")
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

  it "rejects partial trip coordinates" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    login_as(account_id)

    post "/hikes", {
      "name" => "Half Pin Ridge",
      "hiked_at" => "2026-05-17",
      "lat" => "45.4",
      "lng" => ""
    }

    expect(last_response.status).to eq(422)
    expect(last_response.body).to include("Drop a map pin with both latitude and longitude")
    expect(WentHiking::Models::Trip.first(name: "Half Pin Ridge")).to be_nil
  end

  it "autosaves draft fields without publishing them" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    login_as(account_id)
    post "/hikes/drafts"
    trip = WentHiking::Models::Trip[JSON.parse(last_response.body).fetch("trip_id")]

    post "#{trip.public_path}/autosave", {
      "name" => "Cooper Spur",
      "hiked_at" => "2026-05-17",
      "nights" => "2",
      "mileage" => "9.25",
      "elevation" => "2600",
      "source_url" => "https://example.com/cooper",
      "lat" => "45.4",
      "lng" => "-121.7",
      "report_markdown" => "Windy up high.\n\n{{ photo:1 }}"
    }

    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)).to include("saved_at")

    trip.refresh
    expect(trip.name).to eq("Cooper Spur")
    expect(trip.nights).to eq(2)
    expect(trip.mileage).to eq(9.25)
    expect(trip.elevation).to eq(2600)
    expect(trip.source_url).to eq("https://example.com/cooper")
    expect(trip.lat).to eq(45.4)
    expect(trip.report_markdown).to eq("Windy up high.\n\n{{ photo:1 }}")
    # The whole point: still a draft, still on its placeholder slug, still unpublished.
    expect(trip.status).to eq("draft")
    expect(trip.slug).to eq("untitled-hike")
    expect(trip.published_at).to be_nil

    get "/hikes"
    expect(last_response.body).not_to include("Cooper Spur")
  end

  it "keeps autosave partial and forgiving" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    login_as(account_id)
    post "/hikes/drafts"
    trip = WentHiking::Models::Trip[JSON.parse(last_response.body).fetch("trip_id")]

    post "#{trip.public_path}/autosave", {"name" => "Half Typed", "mileage" => "8.", "nights" => "one", "lat" => "45.4", "lng" => ""}

    expect(last_response.status).to eq(422)
    errors = JSON.parse(last_response.body).fetch("errors")
    expect(errors).to include("nights", "location")
    expect(errors["location"]).to include("both latitude and longitude")

    # The fields that parsed are saved anyway; a half-typed number never costs
    # the writer the sentence they were in the middle of.
    trip.refresh
    expect(trip.name).to eq("Half Typed")
    expect(trip.nights).to eq(0)
    expect(trip.lat).to be_nil
    expect(trip.lng).to be_nil
  end

  it "blanks a draft name back to the placeholder rather than storing nothing" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    login_as(account_id)
    post "/hikes/drafts"
    trip = WentHiking::Models::Trip[JSON.parse(last_response.body).fetch("trip_id")]

    post "#{trip.public_path}/autosave", {"name" => "   "}

    expect(last_response.status).to eq(200)
    expect(trip.refresh.name).to eq("Untitled Hike")
  end

  it "stores condition flags and reads them back as the conditions line" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    login_as(account_id)

    post "/hikes", {
      "name" => "Ramona Falls",
      "hiked_at" => "2026-07-04",
      "beauty" => "sublime",
      "mosquitoes" => "none",
      "wildflowers" => "blooming",
      "swimming" => "off_season",
      "snow" => "patches",
      "crowds" => "solitude"
    }

    trip = WentHiking::Models::Trip.first(name: "Ramona Falls")
    expect(trip[:beauty]).to eq("sublime")
    expect(trip[:mosquitoes]).to eq("none")
    expect(trip[:wildflowers]).to eq("blooming")
    expect(trip[:swimming]).to eq("off_season")
    expect(trip[:snow]).to eq("patches")
    expect(trip[:crowds]).to eq("solitude")

    get trip.public_path
    expect(last_response.body).to include("trip-conditions")
    ["sublime", "no mosquitoes", "wildflowers blooming", "too cold to swim", "snow patches", "solitude"].each do |label|
      expect(last_response.body).to include(label)
    end

    # A hike with no flags keeps the header it has always had.
    bare_id = WentHiking.db[:trips].insert(account_id: account_id, name: "Bare Hike", slug: "bare-hike", nights: 0, hiked_at: Time.utc(2026, 7, 1), report_markdown: "", created_at: Time.now, updated_at: Time.now)
    get WentHiking::Models::Trip[bare_id].public_path
    expect(last_response.body).not_to include("trip-conditions")
  end

  it "refuses condition flags outside the vocabulary" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    login_as(account_id)

    post "/hikes", {"name" => "Meh Ridge", "hiked_at" => "2026-05-17", "beauty" => "meh"}

    expect(last_response.status).to eq(422)
    expect(last_response.body).to include("Beauty isn&#39;t one of the offered choices.")
    expect(WentHiking::Models::Trip.first(name: "Meh Ridge")).to be_nil
  end

  it "autosaves condition flags, clears them, and refuses unknown tokens" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    login_as(account_id)
    post "/hikes/drafts"
    trip = WentHiking::Models::Trip[JSON.parse(last_response.body).fetch("trip_id")]

    post "#{trip.public_path}/autosave", {"swimming" => "swam", "mosquitoes" => "swarms"}

    expect(last_response.status).to eq(200)
    trip.refresh
    expect(trip[:swimming]).to eq("swam")
    expect(trip[:mosquitoes]).to eq("swarms")

    # Tapping the set word again sends the field back empty, which is a clear,
    # not an omission: the column goes back to NULL and its neighbours stay.
    post "#{trip.public_path}/autosave", {"swimming" => ""}

    expect(last_response.status).to eq(200)
    trip.refresh
    expect(trip[:swimming]).to be_nil
    expect(trip[:mosquitoes]).to eq("swarms")

    post "#{trip.public_path}/autosave", {"snow" => "hip-deep", "name" => "Still Saved"}

    expect(last_response.status).to eq(422)
    expect(JSON.parse(last_response.body).fetch("errors")).to include("snow")
    trip.refresh
    expect(trip[:snow]).to be_nil
    expect(trip.name).to eq("Still Saved")
  end

  it "renders the condition flags in the compose editor with the saved choice checked" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    trip_id = WentHiking.db[:trips].insert(account_id: account_id, name: "Burnt Lake", slug: "burnt-lake", nights: 0, hiked_at: Time.utc(2026, 7, 1), report_markdown: "", beauty: "beautiful", created_at: Time.now, updated_at: Time.now)
    trip = WentHiking::Models::Trip[trip_id]
    login_as(account_id)

    get "#{trip.public_path}/edit"

    expect(last_response.body).to include("data-compose-conditions")
    expect(last_response.body).to match(/name="beauty"\s+value="beautiful"\s+checked/)
    expect(last_response.body).not_to match(/name="snow"\s+value="[^"]+"\s+checked/)
  end

  it "refuses to autosave a published hike" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    trip_id = WentHiking.db[:trips].insert(account_id: account_id, name: "Burnt Lake", slug: "burnt-lake", nights: 0, hiked_at: Time.utc(2026, 7, 1), report_markdown: "Original.", created_at: Time.now, updated_at: Time.now)
    trip = WentHiking::Models::Trip[trip_id]
    login_as(account_id)

    post "#{trip.public_path}/autosave", {"name" => "Renamed", "report_markdown" => "Overwritten."}

    expect(last_response.status).to eq(422)
    expect(trip.refresh.name).to eq("Burnt Lake")
    expect(trip.report_markdown).to eq("Original.")
  end

  it "only lets the owner autosave" do
    owner_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    intruder_id = WentHiking.db[:accounts].insert(email: "nope@example.com", name: "Nope", slug: "nope", status_id: 2, created_at: Time.now, updated_at: Time.now)
    trip_id = WentHiking.db[:trips].insert(account_id: owner_id, name: "Untitled Hike", slug: "untitled-hike", nights: 0, status: "draft", hiked_at: Time.utc(2026, 7, 1), report_markdown: "", created_at: Time.now, updated_at: Time.now)
    trip = WentHiking::Models::Trip[trip_id]

    post "#{trip.public_path}/autosave", {"name" => "Anonymous edit"}
    expect(last_response.status).to eq(302)
    expect(trip.refresh.name).to eq("Untitled Hike")

    login_as(intruder_id)
    post "#{trip.public_path}/autosave", {"name" => "Someone else's edit"}
    expect(last_response.status).to eq(404)
    expect(trip.refresh.name).to eq("Untitled Hike")
  end

  it "deletes a single photo for the owner" do
    owner_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    intruder_id = WentHiking.db[:accounts].insert(email: "nope@example.com", name: "Nope", slug: "nope", status_id: 2, created_at: Time.now, updated_at: Time.now)
    trip_id = WentHiking.db[:trips].insert(account_id: owner_id, name: "Burnt Lake", slug: "burnt-lake", nights: 0, hiked_at: Time.utc(2026, 7, 1), created_at: Time.now, updated_at: Time.now)
    photo_id = WentHiking.db[:photos].insert(account_id: owner_id, trip_id: trip_id, legacy_photo_id: 321, legacy_image_file_name: "lake.jpg", caption: "Lake light", created_at: Time.now, updated_at: Time.now)
    WentHiking.db[:photo_variants].insert(photo_id: photo_id, style: "large", filename: "lake.jpg", s3_key: "system/images/321/large/lake.jpg", created_at: Time.now, updated_at: Time.now)
    trip = WentHiking::Models::Trip[trip_id]

    login_as(intruder_id)
    post "#{trip.public_path}/photos/#{photo_id}/delete"
    expect(last_response.status).to eq(404)
    expect(WentHiking::Models::Photo[photo_id]).not_to be_nil

    login_as(owner_id)
    post "#{trip.public_path}/photos/#{photo_id}/delete"

    expect(last_response.status).to eq(200)
    expect(WentHiking::Models::Photo[photo_id]).to be_nil
    expect(WentHiking.db[:photo_variants].where(photo_id: photo_id).count).to eq(0)
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

  it "supports direct-to-S3 photo uploads for authenticated trip owners" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    trip_id = WentHiking.db[:trips].insert(account_id: account_id, name: "Burnt Lake", slug: "burnt-lake", nights: 0, hiked_at: Time.utc(2026, 5, 1), created_at: Time.now, updated_at: Time.now)
    trip = WentHiking::Models::Trip[trip_id]
    storage = instance_double(
      WentHiking::Storage::S3,
      direct_upload?: true,
      local?: false,
      direct_upload_post: {url: "https://s3.example.test/upload", fields: {"key" => "system/images/1/original/lake.jpg"}},
      object_exists?: true,
      read: "\xFF\xD8\xFFjpeg-bytes".b
    )
    allow(WentHiking::Storage).to receive(:current).and_return(storage)
    allow(WentHiking::PhotoMetadata).to receive(:extract).and_return(width: 1600, height: 1200, camera_model: "Trail Camera", taken_at: Time.utc(2026, 4, 30, 18, 12))
    allow(WentHiking::PhotoVariantJob).to receive(:enqueue_photo)
    login_as(account_id)

    post "#{trip.public_path}/photos/direct-upload", {
      "filename" => "lake view.jpg",
      "content_type" => "image/jpeg",
      "file_size" => "4096",
      "caption" => "Lake light"
    }

    payload = JSON.parse(last_response.body)
    photo = WentHiking::Models::Photo.first(caption: "Lake light")
    original = photo.variant("original")

    expect(last_response.status).to eq(201)
    expect(payload["upload"]["url"]).to eq("https://s3.example.test/upload")
    expect(payload["finalize_url"]).to eq("#{trip.public_path}/photos/#{photo.id}/finalize")
    expect(original.s3_key).to eq("system/images/#{photo.id}/original/lake-view.jpg")

    post payload.fetch("finalize_url")

    expect(last_response).to be_ok
    expect(photo.refresh.width).to eq(1600)
    expect(photo.camera_model).to eq("Trail Camera")
    # Finalize is when the EXIF day first exists, and the editor dates the
    # hike from exactly this field of the response.
    expect(JSON.parse(last_response.body)["taken_on"]).to eq("2026-04-30")
    expect(WentHiking::PhotoVariantJob).to have_received(:enqueue_photo).with(photo.id)
  end

  it "supports multiple direct uploads and caption updates on draft hikes" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    storage = instance_double(
      WentHiking::Storage::S3,
      direct_upload?: true,
      local?: false,
      direct_upload_post: {url: "https://s3.example.test/upload", fields: {"key" => "system/images/1/original/lake.jpg"}},
      object_exists?: true,
      read: "\xFF\xD8\xFFjpeg-bytes".b
    )
    allow(WentHiking::Storage).to receive(:current).and_return(storage)
    allow(WentHiking::PhotoMetadata).to receive(:extract).and_return(width: 1600, height: 1200)
    allow(WentHiking::PhotoVariantJob).to receive(:enqueue_photo)
    login_as(account_id)

    post "/hikes/drafts"
    draft = WentHiking::Models::Trip[JSON.parse(last_response.body).fetch("trip_id")]

    %w[lake.jpg ridge.jpg].each do |filename|
      post "#{draft.public_path}/photos/direct-upload", {
        "filename" => filename,
        "content_type" => "image/jpeg",
        "file_size" => "4096",
        "caption" => ""
      }
      payload = JSON.parse(last_response.body)
      expect(last_response.status).to eq(201)
      expect(payload["handle"]).to eq("{{ photo:#{payload["id"]} }}")

      post payload.fetch("finalize_url")
      expect(last_response).to be_ok
    end

    photos = draft.refresh.photos_dataset.order(:id).all
    expect(photos.size).to eq(2)
    expect(draft.status).to eq("draft")

    post "#{draft.public_path}/photos/#{photos.first.id}/caption", {"caption" => "Lake light"}

    caption_payload = JSON.parse(last_response.body)
    expect(last_response).to be_ok
    expect(caption_payload["caption"]).to eq("Lake light")
    expect(photos.first.refresh.caption).to eq("Lake light")
  end

  it "renders only current-trip photo handles inline and leaves other photos below the report" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    trip_id = WentHiking.db[:trips].insert(account_id: account_id, name: "Handle Ridge", slug: "handle-ridge", nights: 0, hiked_at: Time.utc(2026, 5, 1), created_at: Time.now, updated_at: Time.now)
    other_trip_id = WentHiking.db[:trips].insert(account_id: account_id, name: "Other Ridge", slug: "other-ridge", nights: 0, hiked_at: Time.utc(2026, 5, 2), created_at: Time.now, updated_at: Time.now)
    inline_photo_id = WentHiking.db[:photos].insert(account_id: account_id, trip_id: trip_id, legacy_image_file_name: "inline.jpg", caption: "Inline light", taken_at: Time.utc(2026, 5, 1, 12), created_at: Time.now, updated_at: Time.now)
    remaining_photo_id = WentHiking.db[:photos].insert(account_id: account_id, trip_id: trip_id, legacy_image_file_name: "remaining.jpg", caption: "Remaining light", taken_at: Time.utc(2026, 5, 1, 13), created_at: Time.now, updated_at: Time.now)
    cross_trip_photo_id = WentHiking.db[:photos].insert(account_id: account_id, trip_id: other_trip_id, legacy_image_file_name: "cross.jpg", caption: "Cross light", taken_at: Time.utc(2026, 5, 2, 12), created_at: Time.now, updated_at: Time.now)
    WentHiking.db[:photo_variants].insert(photo_id: inline_photo_id, style: "large", filename: "inline.jpg", s3_key: "system/images/#{inline_photo_id}/large/inline.jpg", created_at: Time.now, updated_at: Time.now)
    WentHiking.db[:photo_variants].insert(photo_id: remaining_photo_id, style: "large", filename: "remaining.jpg", s3_key: "system/images/#{remaining_photo_id}/large/remaining.jpg", created_at: Time.now, updated_at: Time.now)
    WentHiking.db[:photo_variants].insert(photo_id: cross_trip_photo_id, style: "large", filename: "cross.jpg", s3_key: "system/images/#{cross_trip_photo_id}/large/cross.jpg", created_at: Time.now, updated_at: Time.now)
    WentHiking::Models::Trip[trip_id].update(
      report_markdown: "Before\n\n{{ photo: #{inline_photo_id} }}\n\nAgain {{ photo:#{inline_photo_id} }}\n\nMissing {{ photo:999999 }}\n\nCross {{ photo:#{cross_trip_photo_id} }}"
    )

    get "/hikes/#{trip_id}-handle-ridge"

    expect(last_response).to be_ok
    expect(last_response.body.scan("trip-inline-photo").size).to eq(1)
    expect(last_response.body).to include("Inline light")
    expect(last_response.body).to include("{{ photo:#{inline_photo_id} }}")
    expect(last_response.body).to include("{{ photo:999999 }}")
    expect(last_response.body).to include("{{ photo:#{cross_trip_photo_id} }}")
    expect(last_response.body).to include("trip-photo-gallery")
    expect(last_response.body).to include("remaining.jpg")
    expect(last_response.body).not_to include("cross.jpg")
  end

  it "runs the fallback upload path against a real image" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    trip_id = WentHiking.db[:trips].insert(account_id: account_id, name: "Real Image Ridge", slug: "real-image-ridge", nights: 0, hiked_at: Time.utc(2026, 5, 1), created_at: Time.now, updated_at: Time.now)
    trip = WentHiking::Models::Trip[trip_id]
    fixture_path = make_real_jpeg(File.join(WentHiking.root, "tmp/real-upload-photo.jpg"))
    allow(WentHiking::PhotoVariantJob).to receive(:enqueue_photo)
    login_as(account_id)

    post "#{trip.public_path}/photos", {
      "image" => Rack::Test::UploadedFile.new(fixture_path, "image/jpeg", true),
      "caption" => "Real light"
    }

    photo = WentHiking::Models::Photo.first(caption: "Real light")

    expect(last_response.status).to eq(302)
    expect(photo.width).to eq(800)
    expect(photo.height).to eq(600)
    expect(photo.variant("original").s3_key).to eq("system/images/#{photo.id}/original/real-upload-photo.jpg")
  end

  it "generates photo variants from a real uploaded image" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    trip_id = WentHiking.db[:trips].insert(account_id: account_id, name: "Variant Ridge", slug: "variant-ridge", nights: 0, hiked_at: Time.utc(2026, 5, 1), created_at: Time.now, updated_at: Time.now)
    fixture_path = make_real_jpeg(File.join(WentHiking.root, "tmp/variant-upload-photo.jpg"))
    account = WentHiking::Models::Account[account_id]
    trip = WentHiking::Models::Trip[trip_id]

    result = File.open(fixture_path, "rb") do |io|
      WentHiking::PhotoUpload.new(
        account: account,
        trip: trip,
        upload: {"filename" => "variant upload.jpg", "type" => "image/jpeg", "tempfile" => io},
        caption: "Variant light"
      ).call
    end

    expect(result).to be_success

    WentHiking::PhotoVariantJob.allocate.run(result.photo.id)
    variants = result.photo.refresh.photo_variants_dataset.order(:style).select_map(:style)

    expect(variants).to eq(%w[bpl large medium micro original thumbnail])
    expect(File.exist?(File.join(ENV.fetch("LOCAL_UPLOAD_ROOT"), "system/images/#{result.photo.id}/large/variant-upload.jpg"))).to be(true)
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

    # Post/redirect/get, so a reload of the confirmation is not a resubmission.
    expect(last_response.status).to eq(302)
    expect(last_response.location).to eq("/account?saved=1")
    expect(WentHiking::Models::Account[account_id].name).to eq("Kai Updated")
    expect(WentHiking::Models::Account[account_id].location).to eq("Portland, OR")

    follow_redirect!

    expect(last_response).to be_ok
    expect(last_response.body).to include("Profile saved.")
  end

  it "re-renders the account form in place when it is invalid" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    login_as(account_id)

    post "/account", {"name" => "  ", "location" => "Portland, OR"}

    expect(last_response.status).to eq(422)
    expect(last_response.body).to include("Name is required.")
    expect(WentHiking::Models::Account[account_id].name).to eq("Kai")
  end

  it "redirects old hike ids to canonical paths" do
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    WentHiking.db[:trips].insert(account_id: account_id, legacy_trip_id: 99, name: "Burnt Lake", slug: "burnt-lake", nights: 0, hiked_at: Time.utc(2025, 7, 1), created_at: Time.now, updated_at: Time.now)

    get "/hikes/99"

    expect(last_response.status).to eq(302)
    expect(last_response.location).to include("/hikes/")
  end
end
