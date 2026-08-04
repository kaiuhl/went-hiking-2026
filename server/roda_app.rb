# frozen_string_literal: true

require_relative "../config/boot"
require_relative "response_headers"
require_relative "trip_listing"
require_relative "view_helpers"
require_relative "routes/accounts"
require_relative "routes/api"
require_relative "routes/follows"
require_relative "routes/hikes"
require_relative "routes/mcp"
require_relative "routes/media"
require_relative "routes/pages"
require_relative "routes/people"
require_relative "routes/places"
require_relative "routes/seo"
require_relative "routes/uploads"

require "rack/conditional_get"
require "roda"
require "rodauth"
require "sequel"
require "went_hiking/avatar_upload"
require "went_hiking/email"
require "went_hiking/models"
require "went_hiking/places"

class RodaApp < Roda
  include ResponseHeaders
  include TripListing
  include ViewHelpers
  include AccountRoutes
  include ApiRoutes
  include FollowRoutes
  include HikeRoutes
  include McpRoutes
  include MediaRoutes
  include PageRoutes
  include PeopleRoutes
  include PlaceRoutes
  include SeoRoutes
  include UploadRoutes

  opts[:root] = WentHiking.root

  # An ETag or Last-Modified is only worth sending if something answers the
  # conditional request that comes back with it.
  use Rack::ConditionalGet

  plugin :common_logger
  plugin :head
  plugin :hooks
  plugin :json
  plugin :json_parser
  plugin :public
  plugin :render, engine: "erb", views: "server/views", layout: "layouts/application"
  plugin :sessions, secret: ENV.fetch("SESSION_SECRET", "development-session-secret-change-me-at-deploy-development-session-secret"), key: "went_hiking.session"

  # Tokens are not request-specific because the editor discovers its POST targets
  # at runtime (draft creation rewrites the form action and the upload URLs), so a
  # single token from the layout meta tag has to work for every endpoint.
  plugin :route_csrf, check_header: true, require_request_specific_tokens: false do |_r|
    csrf_failure_response
  end

  plugin :error_handler do |error|
    handle_uncaught_error(error)
  end

  after do |res|
    apply_response_headers(res)
  end

  plugin :rodauth do
    enable :login, :logout, :create_account, :verify_account, :reset_password, :reset_password_verifies_account, :change_password, :lockout,
      :oauth_authorization_code_grant, :oauth_pkce, :oauth_token_revocation, :oauth_dynamic_client_registration

    db WentHiking.db
    base_url WentHiking.public_base_url
    hmac_secret ENV.fetch("RODAUTH_HMAC_SECRET", ENV.fetch("SESSION_SECRET", "development-session-secret-change-me-at-deploy-development-session-secret"))
    login_param "email"
    login_label "Email"
    logout_button "Log out"
    # Auth pages are rendered through the site layout, which titles itself from
    # @title; without this they all read "Went Hiking".
    title_instance_variable :@title
    # The signup fields live in create-account.erb instead of here so the view
    # can order them Name, Email, Password, extras rather than being forced to
    # put every additional tag above the login field.
    require_mail? false
    email_from ENV.fetch("SES_FROM_EMAIL", "Went Hiking <hello@wenthiking.com>")
    use_database_authentication_functions? false
    create_account_autologin? false
    verify_account_set_password? false
    verify_account_autologin? true
    reset_password_autologin? false
    set_deadline_values? true

    # Rodauth renders the resend page in place of the login form on this attempt
    # rather than redirecting, so this flash would not appear on the page it
    # describes — it would surface a request later, on something unrelated. The
    # resend page says it in its own words instead.
    attempt_to_login_to_unverified_account_error_flash nil

    # Only the login page: the same field also appears on signup, where Name
    # comes first and stealing focus past it would be wrong.
    field_attributes do |field|
      (field == login_param && current_route == :login) ? 'autofocus="autofocus"' : ""
    end

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
      scope.honeypot_rejection!
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

      # rodauth-oauth exempts /token and /register outright but only exempts
      # /revoke when the request arrives as JSON — the form-encoded case is left
      # protected for the grant-management screens, which this app does not
      # enable. RFC 7009 revocation is form-encoded, sent by a client that holds
      # the token it is asking to destroy and carries no session cookie, so
      # there is no ambient authority here either. Every other rodauth route,
      # the consent form included, keeps its check.
      def check_csrf?
        (request.path == revoke_path) ? false : super
      end

      # RFC 7591 says to ignore unrecognized client metadata, but rodauth-oauth
      # rejects it -- and Claude registers with its internal "claudeai" scope,
      # which 400ed real connector setups. Sanitize the params in place (the
      # same hash feeds validation, the stored application, and the response)
      # before the strict validation runs.
      def validate_client_registration_params(request_params = request.params)
        request_params.keys.select { |key| unknown_client_metadata?(key) }.each { |key| request_params.delete(key) }

        if request_params["scope"].is_a?(String)
          supported = request_params["scope"].split(" ") & oauth_application_scopes
          if supported.empty?
            request_params.delete("scope")
          else
            request_params["scope"] = supported.join(" ")
          end
        end

        super
      end

      # RFC 8414 metadata fixes for strict clients (Claude's platform, the MCP
      # TS SDK reject the whole document otherwise): unset fields must be
      # omitted rather than null, and code_challenge_methods_supported is an
      # array -- rodauth-oauth emits the bare PKCE method string.
      def oauth_server_metadata_body(*)
        metadata = super
        if metadata[:code_challenge_methods_supported].is_a?(String)
          metadata[:code_challenge_methods_supported] = metadata[:code_challenge_methods_supported].split(" ")
        end
        metadata.reject { |_, value| value.nil? }
      end

      # RFC 7591 defines client_id_issued_at as integer seconds since epoch,
      # but rodauth-oauth emits an ISO 8601 string. Strict clients (Claude's
      # connector platform, the MCP TS SDK) validate the type and treat the
      # whole registration as failed. Standard key for granted scopes is
      # "scope"; the gem only emits its own "scopes".
      def do_register(return_params = request.params.dup)
        params = super
        params["client_id_issued_at"] = Time.now.to_i if params.key?("client_id_issued_at")
        params["scope"] ||= params["scopes"] if params["scopes"].is_a?(String)
        params
      end

      # Assistant clients may request scopes we don't offer (e.g. "claudeai")
      # at the authorization endpoint too; fall back to the server's scopes
      # instead of erroring so consent still renders.
      def scopes
        requested = super
        return requested unless requested.is_a?(Array)

        supported = requested & oauth_application_scopes
        supported.empty? ? oauth_application_scopes : supported
      end

      private

      def unknown_client_metadata?(key)
        return false if %w[
          redirect_uris token_endpoint_auth_method grant_types response_types
          client_uri logo_uri tos_uri policy_uri jwks_uri jwks scope contacts client_name
        ].include?(key)

        !respond_to?(:"oauth_applications_#{key}_column") && !db[oauth_applications_table].columns.include?(key.to_sym)
      end
    end
  end

  route do |r|
    serve_static_assets(r)

    # Authorized by its signed upload ticket rather than the session, so it is
    # deliberately checked before (and exempt from) the CSRF gate.
    route_uploads(r)

    # A bearer token and nothing else: /mcp never reads the session, and a
    # cross-origin form cannot set an Authorization header, so there is no
    # ambient authority for a forged POST to borrow. It also has to run before
    # anything looks at request.params — with json_parser loaded, that would
    # consume the JSON-RPC body the handler is about to read.
    route_mcp(r)

    # Rodauth checks a token on every route it owns, and rodauth-oauth turns
    # that check off for the machine-to-machine endpoints while leaving the
    # browser-facing consent form protected. So the gate for the rest of the
    # site sits behind r.rodauth rather than in front of it; putting it first
    # would reject /token and /register for want of a form field no API client
    # has any way to send.
    r.rodauth

    check_csrf!

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

    route_seo(r)
    route_media(r)
    route_api(r)
    route_account(r)
    route_follows(r)
    route_hikes(r)
    route_people(r)
    route_places(r)
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
    @noindex = true
    request.halt [404, {"Content-Type" => "text/html"}, [view("pages/not_found")]]
  end

  # Never leak a stack trace in production; keep it in development where it helps.
  def handle_uncaught_error(error)
    log_uncaught_error(error)

    @title = "Something Went Sideways"
    @error_kicker = "500"
    @error_heading = "Something slipped off the trail."
    @error_body = "An unexpected error stopped this page from loading. Try again, or head back to the trailhead."
    @error_details = WentHiking.production? ? nil : error_details(error)

    response.status = 500
    if json_request?
      response["Content-Type"] = "application/json"
      JSON.generate({errors: [@error_body]})
    else
      response["Content-Type"] = "text/html"
      view("pages/error")
    end
  end

  # A human never fills the honeypot, but a human is who reads this if one ever
  # does — so it gets the branded page every other refusal gets rather than a
  # line of bare text/plain.
  def honeypot_rejection!
    @title = "Account Not Created"
    @error_kicker = "422"
    @error_heading = "That account could not be created."
    @error_body = "Something in the form did not look right. If you are a person and not a script, please try again."
    @error_details = nil

    response.status = 422
    response["Content-Type"] = "text/html"
    request.halt [422, response.headers, [view("pages/error")]]
  end

  def csrf_failure_response
    message = "Your session expired or the form went stale. Reload the page and try again."
    response.status = 403

    if json_request?
      response["Content-Type"] = "application/json"
      JSON.generate({errors: [message]})
    else
      @title = "Session Expired"
      @error_kicker = "403"
      @error_heading = "That request could not be verified."
      @error_body = message
      @error_details = nil
      response["Content-Type"] = "text/html"
      view("pages/error")
    end
  end

  private

  def json_request?
    return true if request.path.start_with?("/api/")
    return true if request.get_header("HTTP_ACCEPT").to_s.include?("application/json")

    request.get_header("HTTP_SEC_FETCH_DEST") == "empty"
  end

  def error_details(error)
    ["#{error.class}: #{error.message}", *Array(error.backtrace).first(25)].join("\n")
  end

  def log_uncaught_error(error)
    io = request.env["rack.errors"] || $stderr
    io.write("[went-hiking] #{request.request_method} #{request.path} raised #{error.class}: #{error.message}\n")
    Array(error.backtrace).each { |line| io.write("  #{line}\n") }
    io.flush if io.respond_to?(:flush)
  rescue
    nil
  end
end
