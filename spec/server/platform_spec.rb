require_relative "../spec_helper"
require_relative "../../server/roda_app"

require "bcrypt"
require "went_hiking/local_upload_token"

RSpec.describe "platform behaviour" do
  include Rack::Test::Methods
  include CsrfHelpers

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
      report_markdown: "",
      created_at: Time.now,
      updated_at: Time.now
    }.merge(overrides)

    WentHiking::Models::Trip[WentHiking.db[:trips].insert(attributes)]
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

  def upload_root
    ENV.fetch("LOCAL_UPLOAD_ROOT")
  end

  def serve_media_locally!
    allow(WentHiking).to receive(:media_base_url_configured?).and_return(false)
  end

  describe "local direct uploads" do
    it "presigns, accepts the upload, and finalizes with variants on disk" do
      account_id = create_account
      trip = create_trip(account_id)
      fixture = make_real_jpeg(File.join(WentHiking.root, "tmp/direct-local.jpg"))
      login_as(account_id)

      post "#{trip.public_path}/photos/direct-upload", {
        "filename" => "direct local.jpg",
        "content_type" => "image/jpeg",
        "file_size" => File.size(fixture).to_s,
        "caption" => "Local light"
      }

      expect(last_response.status).to eq(201)
      payload = JSON.parse(last_response.body)
      upload = payload.fetch("upload")
      photo = WentHiking::Models::Photo[payload.fetch("photo_id")]

      expect(upload["url"]).to eq("/uploads/direct")
      expect(upload["fields"]).to include("key" => "system/images/#{photo.id}/original/direct-local.jpg", "token" => a_string_matching(/\A[0-9a-f]{64}\z/))

      post_without_csrf "/uploads/direct", upload.fetch("fields").merge(
        "file" => Rack::Test::UploadedFile.new(fixture, "image/jpeg", true)
      )

      expect(last_response.status).to eq(201)
      expect(File.exist?(File.join(upload_root, upload.fetch("fields").fetch("key")))).to be(true)

      post payload.fetch("finalize_url")

      expect(last_response).to be_ok
      expect(photo.refresh.width).to eq(800)
      expect(photo.height).to eq(600)
      expect(photo.photo_variants_dataset.order(:style).select_map(:style)).to eq(%w[bpl large medium micro original thumbnail])
      expect(File.exist?(File.join(upload_root, "system/images/#{photo.id}/large/direct-local.jpg"))).to be(true)

      # Every variant carries the box it actually occupies, including the square
      # crops, whose geometry no amount of arithmetic on the original could
      # recover.
      dimensions = photo.photo_variants_dataset.order(:style).select_map([:style, :width, :height])
      expect(dimensions).to eq([
        ["bpl", 550, 413],
        ["large", 800, 600],
        ["medium", 300, 225],
        ["micro", 25, 25],
        ["original", 800, 600],
        ["thumbnail", 125, 125]
      ])
    end

    it "advertises direct uploads for local storage" do
      expect(WentHiking::Storage.current).to be_direct_upload
      expect(WentHiking::Storage.current).to be_local
    end

    it "rejects a tampered upload ticket" do
      fields = WentHiking::LocalUploadToken.fields(
        key: "system/images/1/original/lake.jpg",
        content_type: "image/jpeg",
        min_bytes: 1024,
        max_bytes: 10_485_760
      )
      fixture = make_real_jpeg(File.join(WentHiking.root, "tmp/tampered.jpg"))

      post_without_csrf "/uploads/direct", fields.merge(
        "key" => "system/images/9/original/elsewhere.jpg",
        "file" => Rack::Test::UploadedFile.new(fixture, "image/jpeg", true)
      )

      expect(last_response.status).to eq(403)
      expect(JSON.parse(last_response.body)["errors"]).to eq(["Upload token is invalid."])
      expect(File.exist?(File.join(upload_root, "system/images/9/original/elsewhere.jpg"))).to be(false)
    end

    it "rejects an expired upload ticket" do
      fields = WentHiking::LocalUploadToken.fields(
        key: "system/images/1/original/lake.jpg",
        content_type: "image/jpeg",
        min_bytes: 1024,
        max_bytes: 10_485_760,
        expires_in: -60
      )
      fixture = make_real_jpeg(File.join(WentHiking.root, "tmp/expired.jpg"))

      post_without_csrf "/uploads/direct", fields.merge(
        "file" => Rack::Test::UploadedFile.new(fixture, "image/jpeg", true)
      )

      expect(last_response.status).to eq(403)
      expect(JSON.parse(last_response.body)["errors"]).to eq(["Upload token has expired."])
    end

    it "rejects a ticket whose key escapes the upload root" do
      result = WentHiking::LocalUploadToken.verify(
        WentHiking::LocalUploadToken.fields(
          key: "system/../../etc/passwd",
          content_type: "image/jpeg",
          min_bytes: 1024,
          max_bytes: 10_485_760
        )
      )

      expect(result).not_to be_valid
      expect(result.error).to eq("Upload token is invalid.")
      expect(WentHiking::Storage.current.path_for("system/../../etc/passwd")).to be_nil
    end

    it "enforces the signed size bounds" do
      fixture = make_real_jpeg(File.join(WentHiking.root, "tmp/too-big.jpg"))
      fields = WentHiking::LocalUploadToken.fields(
        key: "system/images/1/original/lake.jpg",
        content_type: "image/jpeg",
        min_bytes: 1,
        max_bytes: 8
      )

      post_without_csrf "/uploads/direct", fields.merge(
        "file" => Rack::Test::UploadedFile.new(fixture, "image/jpeg", true)
      )

      expect(last_response.status).to eq(422)
      expect(JSON.parse(last_response.body)["errors"]).to eq(["Image file is too large."])
    end

    # The whole attack in one test: an ordinary session asks for a ticket under
    # a .svg name, then posts SVG bytes labelled image/jpeg. Both halves have to
    # fail on their own.
    it "refuses to store an SVG behind an image/jpeg upload ticket" do
      account_id = create_account
      trip = create_trip(account_id)
      login_as(account_id)

      post "#{trip.public_path}/photos/direct-upload", {
        "filename" => "payload.svg",
        "content_type" => "image/jpeg",
        "file_size" => "2048",
        "caption" => ""
      }

      expect(last_response.status).to eq(201)
      payload = JSON.parse(last_response.body)
      key = payload.fetch("upload").fetch("fields").fetch("key")

      # The name the client chose never reaches storage.
      expect(key).to end_with("/payload.jpg")
      expect(key).not_to include(".svg")

      svg = File.join(WentHiking.root, "tmp/payload-spec.svg")
      FileUtils.mkdir_p(File.dirname(svg))
      File.binwrite(svg, %(<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>#{" " * 1200}))

      post_without_csrf "/uploads/direct", payload.fetch("upload").fetch("fields").merge(
        "file" => Rack::Test::UploadedFile.new(svg, "image/jpeg", true)
      )

      expect(last_response.status).to eq(422)
      expect(JSON.parse(last_response.body)["errors"]).to eq(["Image file is not a JPEG, PNG, or GIF."])
      expect(File.exist?(File.join(upload_root, key))).to be(false)
    ensure
      FileUtils.rm_f(File.join(WentHiking.root, "tmp/payload-spec.svg"))
    end

    it "discards a photo whose stored bytes are not the type it promised" do
      account_id = create_account
      trip = create_trip(account_id)
      login_as(account_id)

      post "#{trip.public_path}/photos/direct-upload", {
        "filename" => "lake.jpg",
        "content_type" => "image/jpeg",
        "file_size" => "2048",
        "caption" => ""
      }

      payload = JSON.parse(last_response.body)
      photo_id = payload.fetch("photo_id")
      key = payload.fetch("upload").fetch("fields").fetch("key")

      # Bypass the route entirely: this is the S3 case, where bytes reach the
      # bucket without ever passing through the app.
      WentHiking::Storage.current.put(key, io: StringIO.new("<svg><script>alert(1)</script></svg>"), content_type: "image/jpeg")

      post payload.fetch("finalize_url")

      expect(last_response.status).to eq(422)
      expect(JSON.parse(last_response.body)["errors"]).to eq(["Image file is not a JPEG, PNG, or GIF."])
      expect(WentHiking::Models::Photo[photo_id]).to be_nil
      expect(File.exist?(File.join(upload_root, key))).to be(false)
    end
  end

  describe "local media serving" do
    it "streams stored files when no media host is configured" do
      serve_media_locally!
      WentHiking::Storage.current.put("system/images/7/large/lake.jpg", io: StringIO.new("jpeg-bytes"), content_type: "image/jpeg")

      get "/system/images/7/large/lake.jpg"

      expect(last_response.status).to eq(200)
      expect(last_response.headers["Content-Type"]).to eq("image/jpeg")
      expect(last_response.headers["Cache-Control"]).to eq("public, max-age=86400")
      expect(last_response.body).to eq("jpeg-bytes")
    end

    it "returns 304 for a matching ETag" do
      serve_media_locally!
      WentHiking::Storage.current.put("system/images/7/large/lake.jpg", io: StringIO.new("jpeg-bytes"), content_type: "image/jpeg")

      get "/system/images/7/large/lake.jpg"
      etag = last_response.headers["ETag"]

      header "If-None-Match", etag
      get "/system/images/7/large/lake.jpg"

      expect(last_response.status).to eq(304)
    end

    it "404s for missing local media" do
      serve_media_locally!

      get "/system/images/7/large/missing.jpg"

      expect(last_response.status).to eq(404)
    end

    it "refuses to traverse out of the upload root" do
      serve_media_locally!

      get "/system/../../etc/passwd"
      expect(last_response.status).to eq(404)

      get "/system/%2e%2e/%2e%2e/etc/passwd"
      expect(last_response.status).to eq(404)
    end

    it "still redirects when a media host is configured" do
      get "/system/images/32585/large/image.jpg"

      expect(last_response.status).to eq(302)
      expect(last_response.location).to eq("https://media.example.test/system/images/32585/large/image.jpg")
    end

    it "ships a photo placeholder asset" do
      get "/images/photo-placeholder.svg"

      expect(last_response).to be_ok
      expect(last_response.body).to include("<svg")
    end

    # A stored object's extension is what decides its Content-Type, so an SVG
    # that somehow reached storage must not come back out as one.
    it "never serves stored media as a script-capable type" do
      serve_media_locally!
      WentHiking::Storage.current.put("system/images/7/original/payload.svg", io: StringIO.new("<svg><script>alert(1)</script></svg>"), content_type: "image/jpeg")

      get "/system/images/7/original/payload.svg"

      expect(last_response.status).to eq(200)
      expect(last_response.headers["Content-Type"]).to eq("application/octet-stream")
      expect(last_response.headers["X-Content-Type-Options"]).to eq("nosniff")
      expect(last_response.headers["Content-Security-Policy"]).to eq("default-src 'none'; sandbox")
      expect(MediaRoutes::CONTENT_TYPES.values).not_to include(a_string_matching(/svg|html|xml/))
    end
  end

  describe "response headers" do
    it "sends the security headers on every kind of response" do
      %w[/about /images/photo-placeholder.svg /nope].each do |path|
        get path

        expect(last_response.headers["X-Content-Type-Options"]).to eq("nosniff"), "missing on #{path}"
        expect(last_response.headers["Referrer-Policy"]).to eq("strict-origin-when-cross-origin"), "missing on #{path}"
        expect(last_response.headers["X-Frame-Options"]).to eq("DENY"), "missing on #{path}"
      end
    end

    it "caches a versioned static asset forever and an unversioned one briefly" do
      get "/styles/site.css?v=123"
      versioned = last_response

      expect(versioned.headers["Cache-Control"]).to eq("public, max-age=31536000, immutable")
      expect(versioned.headers["ETag"]).to match(/\A"[0-9a-f]+-[0-9a-f]+"\z/)

      get "/styles/site.css"

      expect(last_response.headers["Cache-Control"]).to eq("public, max-age=604800")
      expect(last_response.headers["ETag"]).to eq(versioned.headers["ETag"])
    end

    it "answers a conditional request for a static asset with 304" do
      get "/styles/site.css?v=123"

      header "If-None-Match", last_response.headers["ETag"]
      get "/styles/site.css?v=123"

      expect(last_response.status).to eq(304)
    end

    it "leaves rendered pages uncached" do
      get "/about"

      expect(last_response.headers["Cache-Control"]).to be_nil
      expect(last_response.headers["ETag"]).to be_nil
    end
  end

  describe "draft lifecycle" do
    it "reuses the account's existing empty draft" do
      account_id = create_account
      login_as(account_id)

      post "/hikes/drafts"
      first_id = JSON.parse(last_response.body).fetch("trip_id")

      post "/hikes/drafts"
      second_id = JSON.parse(last_response.body).fetch("trip_id")

      expect(second_id).to eq(first_id)
      expect(WentHiking::Models::Trip.where(account_id: account_id).count).to eq(1)
    end

    it "sweeps stale empty drafts and keeps ones with work in them" do
      account_id = create_account
      stale = create_trip(account_id, name: "Untitled Hike", slug: "untitled-hike", status: "draft", created_at: Time.now - (8 * 86_400))
      stale_extra = create_trip(account_id, name: "Untitled Hike", slug: "untitled-hike", status: "draft", created_at: Time.now - (9 * 86_400))
      written = create_trip(account_id, name: "Untitled Hike", slug: "untitled-hike", status: "draft", report_markdown: "Started writing.", created_at: Time.now - (10 * 86_400))
      photographed = create_trip(account_id, name: "Untitled Hike", slug: "untitled-hike", status: "draft", created_at: Time.now - (11 * 86_400))
      WentHiking.db[:photos].insert(account_id: account_id, trip_id: photographed.id, legacy_image_file_name: "lake.jpg", created_at: Time.now, updated_at: Time.now)
      login_as(account_id)

      post "/hikes/drafts"

      reused = JSON.parse(last_response.body).fetch("trip_id")
      expect(reused).to eq(stale.id)
      expect(WentHiking::Models::Trip[stale_extra.id]).to be_nil
      expect(WentHiking::Models::Trip[written.id]).not_to be_nil
      expect(WentHiking::Models::Trip[photographed.id]).not_to be_nil
    end

    it "leaves other accounts' drafts alone" do
      account_id = create_account
      other_id = create_account(email: "other@example.com", name: "Other", slug: "other")
      other_draft = create_trip(other_id, name: "Untitled Hike", slug: "untitled-hike", status: "draft", created_at: Time.now - (30 * 86_400))
      login_as(account_id)

      post "/hikes/drafts"

      expect(WentHiking::Models::Trip[other_draft.id]).not_to be_nil
      expect(JSON.parse(last_response.body).fetch("trip_id")).not_to eq(other_draft.id)
    end

    it "surfaces a titled draft on the owner's profile and on nobody else's view of it" do
      account_id = create_account
      draft = create_trip(account_id, name: "Half A Ridge", slug: "half-a-ridge", status: "draft", report_markdown: "Started writing.")
      create_trip(account_id, name: "Burnt Lake", slug: "burnt-lake")
      profile = "/people/#{account_id}-kai"

      get profile
      expect(last_response).to be_ok
      expect(last_response.body).not_to include("profile-draft-list")
      expect(last_response.body).not_to include("Half A Ridge")

      other_id = create_account(email: "other@example.com", name: "Other", slug: "other")
      login_as(other_id)
      get profile

      expect(last_response).to be_ok
      expect(last_response.body).not_to include("profile-draft-list")
      expect(last_response.body).not_to include("Half A Ridge")

      clear_cookies
      login_as(account_id)
      get profile

      expect(last_response).to be_ok
      expect(last_response.body).to include("profile-draft-list")
      expect(last_response.body).to include("Half A Ridge")
      expect(last_response.body).to include(%(href="#{draft.public_path}/edit"))
      expect(last_response.body).to include(%(action="#{draft.public_path}/delete"))
    end

    it "keeps the untouched scratch draft off the profile and lists it once it holds work" do
      account_id = create_account
      create_trip(account_id, name: "Untitled Hike", slug: "untitled-hike", status: "draft")
      login_as(account_id)

      get "/people/#{account_id}-kai"

      expect(last_response).to be_ok
      expect(last_response.body).not_to include("profile-draft-list")

      written = create_trip(account_id, name: "Untitled Hike", slug: "untitled-hike", status: "draft", report_markdown: "Started writing.")

      get "/people/#{account_id}-kai"

      expect(last_response.body).to include("profile-draft-list")
      expect(last_response.body.scan("profile-draft-link").size).to eq(1)
      expect(last_response.body).to include(%(href="#{written.public_path}/edit"))
    end

    it "applies photo captions when creating a hike" do
      account_id = create_account
      trip = create_trip(account_id, name: "Draft", slug: "draft", status: "draft")
      photo_id = WentHiking.db[:photos].insert(account_id: account_id, trip_id: trip.id, legacy_image_file_name: "lake.jpg", created_at: Time.now, updated_at: Time.now)
      login_as(account_id)

      post trip.public_path, {
        "name" => "Captioned Ridge",
        "hiked_at" => "2026-05-17",
        "nights" => "0",
        "report_markdown" => "Nice.",
        "photo_captions" => {photo_id.to_s => "Edited caption"}
      }

      expect(last_response.status).to eq(302)
      expect(WentHiking::Models::Photo[photo_id].caption).to eq("Edited caption")
    end

    it "applies photo captions on the create path too" do
      account_id = create_account
      login_as(account_id)

      post "/hikes/drafts"
      draft = WentHiking::Models::Trip[JSON.parse(last_response.body).fetch("trip_id")]
      photo_id = WentHiking.db[:photos].insert(account_id: account_id, trip_id: draft.id, legacy_image_file_name: "lake.jpg", created_at: Time.now, updated_at: Time.now)

      post "/hikes", {
        "name" => "Fresh Ridge",
        "hiked_at" => "2026-05-17",
        "nights" => "0",
        "report_markdown" => "Nice.",
        "photo_captions" => {photo_id.to_s => "Ignored for another trip"}
      }

      created = WentHiking::Models::Trip.first(name: "Fresh Ridge")
      expect(last_response.status).to eq(302)
      expect(created).not_to be_nil
      expect(WentHiking::Models::Photo[photo_id].caption).to be_nil
    end
  end

  describe "hike deletion" do
    it "destroys the trip, its photos, files, hearts, and comments for the owner" do
      account_id = create_account
      trip = create_trip(account_id)
      photo_id = WentHiking.db[:photos].insert(account_id: account_id, trip_id: trip.id, legacy_image_file_name: "lake.jpg", created_at: Time.now, updated_at: Time.now)
      key = "system/images/#{photo_id}/original/lake.jpg"
      WentHiking.db[:photo_variants].insert(photo_id: photo_id, style: "original", filename: "lake.jpg", s3_key: key, created_at: Time.now, updated_at: Time.now)
      WentHiking.db[:hearts].insert(account_id: account_id, trip_id: trip.id, created_at: Time.now, updated_at: Time.now)
      WentHiking.db[:comments].insert(account_id: account_id, trip_id: trip.id, body_markdown: "Nice", created_at: Time.now, updated_at: Time.now)
      WentHiking::Storage.current.put(key, io: StringIO.new("jpeg-bytes"), content_type: "image/jpeg")
      login_as(account_id)

      post "#{trip.public_path}/delete"

      expect(last_response.status).to eq(302)
      expect(last_response.location).to include("/people/#{account_id}-kai")
      expect(WentHiking::Models::Trip[trip.id]).to be_nil
      expect(WentHiking::Models::Photo[photo_id]).to be_nil
      expect(WentHiking.db[:photo_variants].where(photo_id: photo_id).count).to eq(0)
      expect(WentHiking.db[:hearts].where(trip_id: trip.id).count).to eq(0)
      expect(WentHiking.db[:comments].where(trip_id: trip.id).count).to eq(0)
      expect(File.exist?(File.join(upload_root, key))).to be(false)
    end

    it "refuses to delete another hiker's trip" do
      owner_id = create_account
      intruder_id = create_account(email: "nope@example.com", name: "Nope", slug: "nope")
      trip = create_trip(owner_id)
      login_as(intruder_id)

      post "#{trip.public_path}/delete"

      expect(last_response.status).to eq(404)
      expect(WentHiking::Models::Trip[trip.id]).not_to be_nil
    end

    it "requires authentication to delete" do
      owner_id = create_account
      trip = create_trip(owner_id)

      post "#{trip.public_path}/delete"

      expect(last_response.status).to eq(302)
      expect(last_response.location).to include("/login")
      expect(WentHiking::Models::Trip[trip.id]).not_to be_nil
    end
  end

  describe "CSRF protection" do
    it "renders a token in the layout and in forms" do
      account_id = create_account
      login_as(account_id)

      get "/account"

      expect(last_response.body).to match(/<meta name="csrf-token" content="[^"]+">/)
      expect(last_response.body).to include('<input type="hidden" name="_csrf"')
    end

    it "rejects posts without a token" do
      account_id = create_account
      login_as(account_id)

      post_without_csrf "/account", {"name" => "Hacked"}

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include("could not be verified")
      expect(WentHiking::Models::Account[account_id].name).to eq("Kai")
    end

    it "accepts the token from the request header" do
      account_id = create_account
      login_as(account_id)
      get "/about"
      token = last_response.body[CsrfHelpers::CSRF_META_PATTERN, 1]

      header "X-CSRF-Token", token
      post_without_csrf "/account", {"name" => "Kai Updated"}

      # A successful save redirects, so getting past the CSRF gate is a 302.
      expect(last_response.status).to eq(302)
      expect(WentHiking::Models::Account[account_id].name).to eq("Kai Updated")
    end

    it "answers JSON endpoints with a JSON error" do
      post_without_csrf "/api/markdown-preview", {"body" => "hi"}

      expect(last_response.status).to eq(403)
      expect(JSON.parse(last_response.body)["errors"].first).to include("Reload the page")
    end
  end

  describe "email delivery fallback" do
    before do
      @outbox = File.join(WentHiking.root, "tmp/spec-outbox")
      FileUtils.rm_rf(@outbox)
      allow(WentHiking).to receive(:test?).and_return(false)
      allow(WentHiking::Email).to receive(:outbox_dir).and_return(@outbox)
      allow(WentHiking::Email).to receive(:from_address).and_return("")
    end

    it "writes an eml to the outbox instead of raising when SES is unconfigured" do
      message = WentHiking::Email.render(to: "hiker@example.com", subject: "Verify Account", body: "Please verify.")

      expect { WentHiking::Email.deliver(message) }.not_to raise_error

      files = Dir[File.join(@outbox, "*.eml")]
      expect(files.size).to eq(1)
      contents = File.read(files.first)
      expect(contents).to include("From: Went Hiking <hello@wenthiking.com>")
      expect(contents).to include("To: hiker@example.com")
      expect(contents).to include("Subject: #{message.subject}")
      expect(contents).to include("Content-Type: multipart/alternative")
      expect(contents).to include("Content-Type: text/plain; charset=UTF-8")
      expect(contents).to include("Content-Type: text/html; charset=UTF-8")
      expect(contents).to include(message.text_body)
    end

    it "completes account creation without SES configured" do
      post "/create-account", {
        "email" => "outbox@example.com",
        "name" => "Outbox Hiker",
        "password" => "long-enough-password",
        "password-confirm" => "long-enough-password",
        "website" => ""
      }

      expect(last_response.status).to eq(302)
      expect(WentHiking.db[:accounts].where(email: "outbox@example.com").count).to eq(1)
      expect(Dir[File.join(@outbox, "*.eml")].size).to eq(1)
    end
  end

  describe "error handling" do
    before do
      allow(WentHiking::Models::Trip).to receive(:published).and_raise("kaboom in the backcountry")
    end

    it "renders a branded page without a trace in production" do
      allow(WentHiking).to receive(:production?).and_return(true)

      get "/hikes"

      expect(last_response.status).to eq(500)
      expect(last_response.body).to include("Something slipped off the trail.")
      expect(last_response.body).not_to include("kaboom in the backcountry")
      expect(last_response.body).not_to include("roda_app.rb:")
    end

    it "keeps the trace outside production" do
      allow(WentHiking).to receive(:production?).and_return(false)

      get "/hikes"

      expect(last_response.status).to eq(500)
      expect(last_response.body).to include("Something slipped off the trail.")
      expect(last_response.body).to include("kaboom in the backcountry")
    end
  end
end
