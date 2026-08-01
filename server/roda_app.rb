# frozen_string_literal: true

require_relative "../config/boot"
require_relative "view_helpers"
require_relative "routes/accounts"
require_relative "routes/api"
require_relative "routes/follows"
require_relative "routes/hikes"
require_relative "routes/mcp"
require_relative "routes/media"
require_relative "routes/pages"
require_relative "routes/people"

require "roda"
require "rodauth"
require "sequel"
require "went_hiking/avatar_upload"
require "went_hiking/email"
require "went_hiking/models"

class RodaApp < Roda
  include ViewHelpers
  include AccountRoutes
  include ApiRoutes
  include FollowRoutes
  include HikeRoutes
  include McpRoutes
  include MediaRoutes
  include PageRoutes
  include PeopleRoutes

  opts[:root] = WentHiking.root

  plugin :common_logger
  plugin :head
  plugin :json
  plugin :json_parser
  plugin :public
  plugin :render, engine: "erb", views: "server/views", layout: "layouts/application"
  plugin :sessions, secret: ENV.fetch("SESSION_SECRET", "development-session-secret-change-me-at-deploy-development-session-secret"), key: "went_hiking.session"
  plugin :rodauth, csrf: false do
    enable :login, :logout, :create_account, :verify_account, :reset_password, :reset_password_verifies_account, :change_password, :lockout,
      :oauth_authorization_code_grant, :oauth_pkce, :oauth_token_revocation, :oauth_dynamic_client_registration

    db WentHiking.db
    base_url WentHiking.public_base_url
    hmac_secret ENV.fetch("RODAUTH_HMAC_SECRET", ENV.fetch("SESSION_SECRET", "development-session-secret-change-me-at-deploy-development-session-secret"))
    login_param "email"
    login_label "Email"
    create_account_additional_form_tags <<~HTML
      <div class="form-row">
        <label for="name">Name</label>
        <input id="name" name="name" autocomplete="name" required>
        <p class="inline-hints">This can be real or fake, but real is preferable. Let's be friends, not strangers.</p>
      </div>
      <div class="form-row">
        <label for="location">Locale</label>
        <input id="location" name="location" autocomplete="address-level2">
        <p class="inline-hints">This helps us show relevant nearby trips.</p>
      </div>
      <div class="form-row">
        <label for="avatar">A photo of you</label>
        <input id="avatar" name="avatar" type="file" accept="image/jpeg,image/png,image/gif">
        <p class="inline-hints">Upload a photo to represent yourself. This will be cropped into a square later.</p>
      </div>
      <div class="honey-field" aria-hidden="true">
        <label for="website">Website</label>
        <input id="website" name="website" tabindex="-1" autocomplete="off">
      </div>
    HTML
    require_mail? false
    email_from ENV.fetch("SES_FROM_EMAIL", "Went Hiking <hello@wenthiking.com>")
    use_database_authentication_functions? false
    create_account_autologin? false
    verify_account_set_password? false
    verify_account_autologin? true
    reset_password_autologin? false
    set_deadline_values? true

    new_account do |login|
      name = param_or_nil("name").to_s.strip
      name = login.to_s.split("@").first if name.empty?
      now = Time.now

      {
        email: login.to_s.strip.downcase,
        name: name,
        slug: WentHiking::Slug.generate(name),
        location: param_or_nil("location").to_s.strip.empty? ? nil : param_or_nil("location").to_s.strip,
        status_id: account_initial_status_value,
        created_at: now,
        updated_at: now
      }
    end

    before_create_account do
      next if param_or_nil("website").to_s.empty?

      db[:signup_attempts].insert(
        email: param_or_nil(login_param),
        ip_address: request.ip,
        user_agent: request.user_agent,
        honeypot_filled: true,
        result: "honeypot_blocked",
        created_at: Time.now
      )
      set_error_flash "There was an error creating your account"
      request.halt [422, {}, ["There was an error creating your account"]]
    end

    after_create_account do
      avatar_upload = request.POST["avatar"]
      if WentHiking::AvatarUpload.present?(avatar_upload)
        WentHiking::AvatarUpload.new(account: WentHiking::Models::Account[account[account_id_column]], upload: avatar_upload).call
      end

      db[:signup_attempts].insert(
        email: account[login_column],
        ip_address: request.ip,
        user_agent: request.user_agent,
        honeypot_filled: false,
        result: "created_pending_verification",
        created_at: Time.now
      )
      super()
    end

    create_email do |subject, body|
      WentHiking::Email.render(to: email_to, subject: "#{email_subject_prefix}#{subject}", body: body)
    end

    send_email do |email|
      WentHiking::Email.deliver(email)
    end

    # OAuth 2.1 authorization server backing the MCP connector. Assistant
    # clients (Claude, ChatGPT) register themselves as public clients via
    # dynamic client registration and authenticate members through the normal
    # login page; access tokens are then presented to POST /mcp.
    oauth_application_scopes WentHiking::Mcp::SCOPES
    oauth_token_endpoint_auth_methods_supported %w[client_secret_basic client_secret_post none]
    oauth_response_mode "query"
    oauth_valid_uri_schemes(WentHiking.production? ? %w[https] : %w[http https])
    oauth_authorize_button "Allow access"

    before_register {} # open registration: MCP clients are public clients bound by PKCE + member login

    auth_class_eval do
      # Public wrapper so the /mcp route can resolve bearer tokens without
      # touching request params (rodauth's resource-server helpers are private).
      def mcp_grant_for_token(token)
        oauth_grant_by_token(token)
      end
    end
  end

  route do |r|
    r.public
    r.rodauth

    r.get "health" do
      json_payload({status: "ok"})
    end

    # RFC 9728 protected resource metadata, so MCP clients can discover the
    # authorization server from a bare /mcp URL. The path-suffixed variant
    # covers clients that append the resource path per the RFC.
    r.get ".well-known/oauth-protected-resource" do
      json_payload(oauth_protected_resource_metadata)
    end

    r.get ".well-known/oauth-protected-resource/mcp" do
      json_payload(oauth_protected_resource_metadata)
    end

    # RFC 8414 authorization server metadata (/.well-known/oauth-authorization-server).
    rodauth.load_oauth_server_metadata_route

    route_mcp(r)
    route_media(r)
    route_api(r)
    route_account(r)
    route_follows(r)
    route_hikes(r)
    route_people(r)
    route_pages(r)

    not_found
  end

  def oauth_protected_resource_metadata
    base = WentHiking.public_base_url.to_s.sub(%r{/+\z}, "")

    {
      resource: "#{base}/mcp",
      authorization_servers: [base],
      scopes_supported: WentHiking::Mcp::SCOPES,
      bearer_methods_supported: ["header"],
      resource_name: "Went Hiking"
    }
  end

  def json_payload(payload, status: 200)
    response.status = status
    response["Content-Type"] = "application/json"
    JSON.generate(payload)
  end

  def redirect(path, status = 302)
    response.redirect(path, status)
  end

  def not_found
    @title = "Not Found"
    request.halt [404, {"Content-Type" => "text/html"}, [view("pages/not_found")]]
  end
end
