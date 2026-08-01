# frozen_string_literal: true

require_relative "../config/boot"
require_relative "view_helpers"
require_relative "routes/accounts"
require_relative "routes/api"
require_relative "routes/follows"
require_relative "routes/hikes"
require_relative "routes/media"
require_relative "routes/pages"
require_relative "routes/people"
require_relative "routes/uploads"

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
  include MediaRoutes
  include PageRoutes
  include PeopleRoutes
  include UploadRoutes

  opts[:root] = WentHiking.root

  plugin :common_logger
  plugin :head
  plugin :json
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

  plugin :rodauth do
    enable :login, :logout, :create_account, :verify_account, :reset_password, :reset_password_verifies_account, :change_password, :lockout

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
  end

  route do |r|
    r.public

    # Authorized by its signed upload ticket rather than the session, so it is
    # deliberately checked before (and exempt from) the CSRF gate.
    route_uploads(r)

    check_csrf!
    r.rodauth

    r.get "health" do
      json_payload({status: "ok"})
    end

    route_media(r)
    route_api(r)
    route_account(r)
    route_follows(r)
    route_hikes(r)
    route_people(r)
    route_pages(r)

    not_found
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
