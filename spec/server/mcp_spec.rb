# frozen_string_literal: true

require_relative "../spec_helper"
require_relative "../../server/roda_app"

require "base64"
require "bcrypt"
require "digest"
require "securerandom"

RSpec.describe "MCP connector" do
  include Rack::Test::Methods

  def app
    RodaApp.app
  end

  def redirect_uri
    "https://claude.ai/api/mcp/auth_callback"
  end

  def create_account(email: "hiker@example.com", name: "Kai Hiker")
    account_id = WentHiking.db[:accounts].insert(
      email: email,
      name: name,
      slug: WentHiking::Slug.generate(name),
      status_id: 2,
      created_at: Time.now,
      updated_at: Time.now
    )
    WentHiking::Models::Account[account_id]
  end

  def login_as(account, password: "long-enough-password")
    WentHiking.db[:account_password_hashes].insert(id: account.id, password_hash: BCrypt::Password.create(password).to_s)
    post "/login", {"email" => account.email, "password" => password}
    expect(last_response.status).to eq(302)
  end

  def register_client(metadata = {})
    payload = {
      client_name: "Claude",
      redirect_uris: [redirect_uri],
      token_endpoint_auth_method: "none",
      grant_types: %w[authorization_code refresh_token],
      response_types: %w[code]
    }.merge(metadata)

    post "/register", JSON.generate(payload), {"CONTENT_TYPE" => "application/json"}
    expect(last_response.status).to eq(201), last_response.body
    JSON.parse(last_response.body)
  end

  def pkce_pair
    verifier = SecureRandom.urlsafe_base64(32)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    [verifier, challenge]
  end

  def authorize_and_fetch_token(account, scopes: %w[hikes:read hikes:write])
    client = register_client
    login_as(account)
    verifier, challenge = pkce_pair
    state = SecureRandom.hex(8)

    get "/authorize", {
      "client_id" => client["client_id"],
      "redirect_uri" => redirect_uri,
      "response_type" => "code",
      "state" => state,
      "code_challenge" => challenge,
      "code_challenge_method" => "S256",
      "scope" => scopes.join(" ")
    }
    expect(last_response.status).to eq(200), last_response.body

    post "/authorize", {
      "client_id" => client["client_id"],
      "redirect_uri" => redirect_uri,
      "response_type" => "code",
      "state" => state,
      "code_challenge" => challenge,
      "code_challenge_method" => "S256",
      "scope" => scopes
    }
    expect(last_response.status).to eq(302), last_response.body

    location = URI(last_response.location)
    expect("#{location.scheme}://#{location.host}#{location.path}").to eq(redirect_uri)
    params = Rack::Utils.parse_query(location.query)
    expect(params["state"]).to eq(state)
    expect(params["code"]).not_to be_nil

    post "/token", {
      "grant_type" => "authorization_code",
      "code" => params["code"],
      "redirect_uri" => redirect_uri,
      "client_id" => client["client_id"],
      "code_verifier" => verifier
    }
    expect(last_response.status).to eq(200), last_response.body
    JSON.parse(last_response.body)
  end

  def mcp_request(token, payload)
    post "/mcp", JSON.generate(payload), {"CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => "Bearer #{token}"}
  end

  def mcp_tool_call(token, name, arguments = {})
    mcp_request(token, {jsonrpc: "2.0", id: 1, method: "tools/call", params: {name: name, arguments: arguments}})
    expect(last_response.status).to eq(200), last_response.body
    result = JSON.parse(last_response.body).fetch("result")
    text = result.fetch("content").first.fetch("text")
    [result, begin
      JSON.parse(text)
    rescue JSON::ParserError
      text
    end]
  end

  describe "discovery" do
    it "serves RFC 9728 protected resource metadata, including the path-suffixed variant" do
      ["/.well-known/oauth-protected-resource", "/.well-known/oauth-protected-resource/mcp"].each do |path|
        get path

        expect(last_response).to be_ok
        metadata = JSON.parse(last_response.body)
        expect(metadata["resource"]).to eq("http://localhost:9292/mcp")
        expect(metadata["authorization_servers"]).to eq(["http://localhost:9292"])
        expect(metadata["scopes_supported"]).to eq(%w[hikes:read hikes:write])
      end
    end

    it "serves RFC 8414 authorization server metadata with PKCE and registration" do
      get "/.well-known/oauth-authorization-server"

      expect(last_response).to be_ok
      metadata = JSON.parse(last_response.body)
      expect(metadata["issuer"]).to eq("http://localhost:9292")
      expect(metadata["authorization_endpoint"]).to eq("http://localhost:9292/authorize")
      expect(metadata["token_endpoint"]).to eq("http://localhost:9292/token")
      expect(metadata["registration_endpoint"]).to eq("http://localhost:9292/register")
      expect(metadata["code_challenge_methods_supported"]).to include("S256")
      expect(metadata["grant_types_supported"]).to include("authorization_code")
      expect(metadata["token_endpoint_auth_methods_supported"]).to include("none")
      expect(metadata["scopes_supported"]).to include("hikes:read", "hikes:write")
    end
  end

  describe "authorization" do
    it "walks dynamic registration, consent, PKCE code exchange, and refresh" do
      account = create_account
      token_payload = authorize_and_fetch_token(account)

      expect(token_payload["access_token"]).not_to be_nil
      expect(token_payload["refresh_token"]).not_to be_nil
      expect(token_payload["token_type"]).to eq("bearer")

      post "/token", {
        "grant_type" => "refresh_token",
        "refresh_token" => token_payload["refresh_token"],
        "client_id" => WentHiking.db[:oauth_applications].first[:client_id]
      }
      expect(last_response.status).to eq(200), last_response.body
      expect(JSON.parse(last_response.body)["access_token"]).not_to be_nil
    end

    it "shows a consent page naming the client and the member" do
      account = create_account
      client = register_client(client_name: "Claude on iPhone")
      login_as(account)
      _, challenge = pkce_pair

      get "/authorize", {
        "client_id" => client["client_id"],
        "redirect_uri" => redirect_uri,
        "response_type" => "code",
        "code_challenge" => challenge,
        "code_challenge_method" => "S256"
      }

      expect(last_response).to be_ok
      expect(last_response.body).to include("Claude on iPhone")
      expect(last_response.body).to include("Kai Hiker")
      expect(last_response.body).to include("hikes:write")
    end

    it "rejects MCP requests without a valid token, pointing at resource metadata" do
      post "/mcp", JSON.generate({jsonrpc: "2.0", id: 1, method: "tools/list"}), {"CONTENT_TYPE" => "application/json"}

      expect(last_response.status).to eq(401)
      expect(last_response.headers["WWW-Authenticate"]).to include('resource_metadata="http://localhost:9292/.well-known/oauth-protected-resource"')

      post "/mcp", JSON.generate({jsonrpc: "2.0", id: 1, method: "tools/list"}), {"CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => "Bearer bogus"}
      expect(last_response.status).to eq(401)
    end

    it "responds 405 to GET /mcp" do
      get "/mcp"
      expect(last_response.status).to eq(405)
    end
  end

  describe "MCP protocol" do
    it "handles initialize, the initialized notification, and tools/list" do
      account = create_account
      token = authorize_and_fetch_token(account).fetch("access_token")

      mcp_request(token, {jsonrpc: "2.0", id: 1, method: "initialize", params: {protocolVersion: "2025-06-18", capabilities: {}, clientInfo: {name: "spec", version: "0"}}})
      expect(last_response.status).to eq(200), last_response.body
      init = JSON.parse(last_response.body)["result"]
      expect(init["serverInfo"]["name"]).to eq("went-hiking")
      expect(init["instructions"]).to include("draft")

      mcp_request(token, {jsonrpc: "2.0", method: "notifications/initialized"})
      expect(last_response.status).to eq(202)

      mcp_request(token, {jsonrpc: "2.0", id: 2, method: "tools/list"})
      tools = JSON.parse(last_response.body)["result"]["tools"].map { |tool| tool["name"] }
      expect(tools).to contain_exactly(
        "list_my_hikes", "get_hike", "create_hike_draft", "update_hike",
        "set_photo_caption", "get_photo_upload_link", "publish_hike"
      )
    end
  end

  describe "tools" do
    let(:account) { create_account }
    let(:token) { authorize_and_fetch_token(account).fetch("access_token") }

    it "creates a draft hike with a photo upload link" do
      result, payload = mcp_tool_call(token, "create_hike_draft", {
        name: "Goat Rocks Loop",
        hiked_at: "2026-07-18",
        nights: 2,
        mileage: 32.5,
        elevation: 6200,
        report_markdown: "What a weekend."
      })

      expect(result["isError"]).to be(false)
      expect(payload["status"]).to eq("draft")
      expect(payload["photo_upload_url"]).to include("/photos/mobile-upload?token=")

      trip = WentHiking::Models::Trip[payload["trip_id"]]
      expect(trip.account_id).to eq(account.id)
      expect(trip.draft?).to be(true)
      expect(trip.name).to eq("Goat Rocks Loop")
      expect(trip.nights).to eq(2)
      expect(trip.mileage).to eq(32.5)
    end

    it "lists and fetches the member's hikes, including drafts" do
      _, created = mcp_tool_call(token, "create_hike_draft", {name: "Burnt Lake", hiked_at: "2026-06-01"})

      _, listing = mcp_tool_call(token, "list_my_hikes", {})
      expect(listing["count"]).to eq(1)
      expect(listing["hikes"].first).to include("name" => "Burnt Lake", "status" => "draft")

      _, details = mcp_tool_call(token, "get_hike", {trip_id: created["trip_id"]})
      expect(details["report_markdown"]).to eq("")
      expect(details["photos"]).to eq([])
    end

    it "updates hikes and publishes drafts, scheduling follower notifications" do
      WentHiking.db[:hike_follow_subscriptions].insert(
        followed_account_id: account.id,
        email: "friend@example.com",
        status: "active",
        created_at: Time.now,
        updated_at: Time.now
      )

      _, created = mcp_tool_call(token, "create_hike_draft", {name: "Goat Rocks", hiked_at: "2026-07-18"})
      trip_id = created["trip_id"]

      _, updated = mcp_tool_call(token, "update_hike", {trip_id: trip_id, report_markdown: "Day one: larches.", mileage: 12})
      expect(updated["report_markdown"]).to eq("Day one: larches.")
      expect(updated["mileage"]).to eq(12)

      result, published = mcp_tool_call(token, "publish_hike", {trip_id: trip_id})
      expect(result["isError"]).to be(false)
      expect(published["status"]).to eq("published")
      expect(published["url"]).to include("/hikes/#{trip_id}-goat-rocks")

      trip = WentHiking::Models::Trip[trip_id]
      expect(trip.published?).to be(true)
      expect(trip.published_at).not_to be_nil
      expect(WentHiking.db[:hike_follow_notifications].where(trip_id: trip_id).count).to eq(1)

      result, again = mcp_tool_call(token, "publish_hike", {trip_id: trip_id})
      expect(result["isError"]).to be(false)
      expect(again["note"]).to include("already published")
    end

    it "refuses to publish an unnamed draft" do
      trip = WentHiking::Models::Trip.create(
        account_id: account.id, name: "Untitled Hike", slug: "untitled-hike",
        hiked_at: Time.now, nights: 0, report_markdown: "", status: "draft", published_at: nil
      )

      result, message = mcp_tool_call(token, "publish_hike", {trip_id: trip.id})
      expect(result["isError"]).to be(true)
      expect(message).to include("real name")
      expect(WentHiking::Models::Trip[trip.id].draft?).to be(true)
    end

    it "sets and clears photo captions" do
      _, created = mcp_tool_call(token, "create_hike_draft", {name: "Photo Hike", hiked_at: "2026-07-01"})
      photo = WentHiking::Models::Photo.create(account_id: account.id, trip_id: created["trip_id"], legacy_stats_added: true)

      _, updated = mcp_tool_call(token, "set_photo_caption", {trip_id: created["trip_id"], photo_id: photo.id, caption: "Golden larches"})
      expect(updated["caption"]).to eq("Golden larches")
      expect(WentHiking::Models::Photo[photo.id].caption).to eq("Golden larches")

      _, cleared = mcp_tool_call(token, "set_photo_caption", {trip_id: created["trip_id"], photo_id: photo.id, caption: ""})
      expect(cleared).not_to include("caption")
      expect(WentHiking::Models::Photo[photo.id].caption).to be_nil
    end

    it "never exposes another member's hikes" do
      other = create_account(email: "other@example.com", name: "Other Hiker")
      other_trip = WentHiking::Models::Trip.create(
        account_id: other.id, name: "Secret Draft", slug: "secret-draft",
        hiked_at: Time.now, nights: 0, report_markdown: "", status: "draft", published_at: nil
      )

      result, message = mcp_tool_call(token, "get_hike", {trip_id: other_trip.id})
      expect(result["isError"]).to be(true)
      expect(message).to include("No hike with id")

      result, = mcp_tool_call(token, "update_hike", {trip_id: other_trip.id, name: "Hijacked"})
      expect(result["isError"]).to be(true)
      expect(WentHiking::Models::Trip[other_trip.id].name).to eq("Secret Draft")
    end

    it "blocks writes when only hikes:read was granted" do
      read_token = authorize_and_fetch_token(account, scopes: %w[hikes:read]).fetch("access_token")

      result, message = mcp_tool_call(read_token, "create_hike_draft", {name: "Nope", hiked_at: "2026-07-01"})
      expect(result["isError"]).to be(true)
      expect(message).to include("hikes:write")
      expect(WentHiking.db[:trips].count).to eq(0)

      _, listing = mcp_tool_call(read_token, "list_my_hikes", {})
      expect(listing["count"]).to eq(0)
    end
  end

  describe "mobile photo upload page" do
    let(:account) { create_account }
    let(:trip) do
      WentHiking::Models::Trip.create(
        account_id: account.id, name: "Goat Rocks", slug: "goat-rocks",
        hiked_at: Time.now, nights: 1, report_markdown: "", status: "draft", published_at: nil
      )
    end

    it "renders with a valid token and no session" do
      get "#{trip.public_path}/photos/mobile-upload", {"token" => WentHiking::UploadTokens.generate(trip)}

      expect(last_response).to be_ok
      expect(last_response.body).to include("Add photos to Goat Rocks")
      expect(last_response.body).to include("data-mobile-upload")
    end

    it "rejects missing, mismatched, and expired tokens" do
      get "#{trip.public_path}/photos/mobile-upload"
      expect(last_response.status).to eq(404)

      other_trip = WentHiking::Models::Trip.create(
        account_id: account.id, name: "Other", slug: "other",
        hiked_at: Time.now, nights: 0, report_markdown: "", status: "draft", published_at: nil
      )
      get "#{trip.public_path}/photos/mobile-upload", {"token" => WentHiking::UploadTokens.generate(other_trip)}
      expect(last_response.status).to eq(404)

      expired = WentHiking::UploadTokens.generate(trip, now: Time.now - WentHiking::UploadTokens::TTL_SECONDS - 60)
      get "#{trip.public_path}/photos/mobile-upload", {"token" => expired}
      expect(last_response.status).to eq(404)
    end

    it "authorizes photo endpoints via upload token instead of a session" do
      photo = WentHiking::Models::Photo.create(account_id: account.id, trip_id: trip.id, legacy_stats_added: true)
      token = WentHiking::UploadTokens.generate(trip)

      post "#{trip.public_path}/photos/#{photo.id}/caption?upload_token=#{token}", {"caption" => "From the phone"}
      expect(last_response).to be_ok
      expect(WentHiking::Models::Photo[photo.id].caption).to eq("From the phone")

      post "#{trip.public_path}/photos/#{photo.id}/caption", {"caption" => "No auth"}
      expect(last_response.status).to eq(302)
      expect(last_response.location).to include("/login")
    end
  end

  describe "instructions page" do
    it "explains how to connect an assistant and is linked from the footer" do
      get "/connect"

      expect(last_response).to be_ok
      expect(last_response.body).to include("http://localhost:9292/mcp")
      expect(last_response.body).to include("Claude")
      expect(last_response.body).to include("ChatGPT")

      get "/about"
      expect(last_response.body).to include(%(<a href="/connect">))
    end
  end

  describe "WentHiking::UploadTokens" do
    it "round-trips and enforces expiry" do
      account = create_account
      trip = WentHiking::Models::Trip.create(
        account_id: account.id, name: "Trip", slug: "trip",
        hiked_at: Time.now, nights: 0, report_markdown: "", status: "draft", published_at: nil
      )

      token = WentHiking::UploadTokens.generate(trip)
      expect(WentHiking::UploadTokens.trip_from(token).id).to eq(trip.id)
      expect(WentHiking::UploadTokens.trip_from("#{token}x")).to be_nil
      expect(WentHiking::UploadTokens.trip_from(token, now: Time.now + WentHiking::UploadTokens::TTL_SECONDS + 1)).to be_nil
    end
  end
end
