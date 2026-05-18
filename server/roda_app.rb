# frozen_string_literal: true

require_relative "../config/boot"
require_relative "view_helpers"
require_relative "routes/accounts"
require_relative "routes/api"
require_relative "routes/hikes"
require_relative "routes/media"
require_relative "routes/pages"
require_relative "routes/people"

require "roda"
require "rodauth"
require "sequel"
require "went_hiking/email"
require "went_hiking/models"

class RodaApp < Roda
  include ViewHelpers
  include AccountRoutes
  include ApiRoutes
  include HikeRoutes
  include MediaRoutes
  include PageRoutes
  include PeopleRoutes

  opts[:root] = WentHiking.root

  plugin :common_logger
  plugin :head
  plugin :json
  plugin :public
  plugin :render, engine: "erb", views: "server/views", layout: "layouts/application"
  plugin :sessions, secret: ENV.fetch("SESSION_SECRET", "development-session-secret-change-me-at-deploy-development-session-secret"), key: "went_hiking.session"
  plugin :rodauth, csrf: false do
    enable :login, :logout, :create_account, :verify_account, :reset_password, :reset_password_verifies_account, :change_password, :lockout

    db WentHiking.db
    base_url WentHiking.public_base_url
    hmac_secret ENV.fetch("RODAUTH_HMAC_SECRET", ENV.fetch("SESSION_SECRET", "development-session-secret-change-me-at-deploy-development-session-secret"))
    login_param "email"
    login_label "Email"
    create_account_additional_form_tags <<~HTML
      <div class="form-row">
        <label for="name">Name</label>
        <input id="name" name="name" autocomplete="name" required>
      </div>
      <div class="honey-field" aria-hidden="true">
        <label for="website">Website</label>
        <input id="website" name="website" tabindex="-1" autocomplete="off">
      </div>
    HTML
    require_mail? false
    email_from ENV.fetch("SES_FROM_EMAIL", "Went Hiking <hello@wenthiking.com>")
    create_account_autologin? false
    verify_account_autologin? true
    reset_password_autologin? false

    new_account do |login|
      name = param_or_nil("name").to_s.strip
      name = login.to_s.split("@").first if name.empty?
      now = Time.now

      {
        email: login.to_s.strip.downcase,
        name: name,
        slug: WentHiking::Slug.generate(name),
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
      WentHiking::Email::Message.new(to: email_to, subject: "#{email_subject_prefix}#{subject}", body: body)
    end

    send_email do |email|
      WentHiking::Email.deliver(email)
    end
  end

  route do |r|
    r.public
    r.rodauth

    r.get "health" do
      json_payload({status: "ok"})
    end

    route_media(r)
    route_api(r)
    route_account(r)
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
end
