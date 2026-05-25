require_relative "../spec_helper"
require_relative "../../server/roda_app"

require "bcrypt"
require "went_hiking/follow_tokens"

RSpec.describe "follow routes" do
  include Rack::Test::Methods

  before do
    WentHiking::Email.clear_deliveries
  end

  def app
    RodaApp.app
  end

  def create_account(name: "Kai", email: "kai@example.com")
    WentHiking::Models::Account.create(email: email, name: name, slug: name.downcase, status_id: 2, created_at: Time.now, updated_at: Time.now)
  end

  def login_as(account_id, password: "long-enough-password")
    WentHiking.db[:account_password_hashes].insert(id: account_id, password_hash: BCrypt::Password.create(password).to_s)
    post "/login", {"email" => WentHiking.db[:accounts].where(id: account_id).get(:email), "password" => password}
    expect(last_response.status).to eq(302)
  end

  it "renders a profile follow form" do
    account = create_account

    get account.public_path

    expect(last_response).to be_ok
    expect(last_response.body).to include("Follow Kai")
    expect(last_response.body).to include(%(action="#{account.public_path}/follow"))
    expect(last_response.body).to include("Confirmation required")
  end

  it "accepts follow requests with generic check-email messaging" do
    account = create_account
    post "#{account.public_path}/follow", {"email" => "trail@example.com", "company" => ""}

    subscription = WentHiking::Models::HikeFollowSubscription.first(email: "trail@example.com")
    expect(last_response.status).to eq(302)
    expect(last_response.location).to include("#{account.public_path}?follow=check-email")
    expect(subscription.status).to eq("pending")
    expect(WentHiking::Email.deliveries.size).to eq(1)

    follow_redirect!

    expect(last_response.body).to include("Check your email to confirm this follow.")
  end

  it "rerenders invalid follow emails with validation errors" do
    account = create_account

    post "#{account.public_path}/follow", {"email" => "oops", "company" => ""}

    expect(last_response.status).to eq(422)
    expect(last_response.body).to include("Enter a valid email address.")
  end

  it "confirms pending follows" do
    account = create_account
    post "#{account.public_path}/follow", {"email" => "trail@example.com", "company" => ""}
    token = WentHiking::Email.deliveries.last.text_body[%r{/follow/confirm/([^ \n]+)}, 1]

    get "/follow/confirm/#{token}"
    subscription = WentHiking::Models::HikeFollowSubscription.first(email: "trail@example.com")

    expect(last_response).to be_ok
    expect(last_response.body).to include("Follow confirmed")
    expect(subscription.status).to eq("active")
    expect(subscription.confirmed_at).not_to be_nil
    expect(subscription.confirmation_token_digest).to be_nil
  end

  it "rejects invalid confirmation links" do
    get "/follow/confirm/not-real"

    expect(last_response.status).to eq(404)
    expect(last_response.body).to include("Follow link expired")
  end

  it "unsubscribes active follows through a signed link" do
    account = create_account
    subscription = WentHiking::Models::HikeFollowSubscription.create(
      followed_account_id: account.id,
      email: "trail@example.com",
      status: "active",
      confirmed_at: Time.now,
      created_at: Time.now,
      updated_at: Time.now
    )
    token = WentHiking::FollowTokens.unsubscribe_token(subscription)

    get "/follow/unsubscribe/#{token}"

    expect(last_response).to be_ok
    expect(last_response.body).to include("Unsubscribed")
    expect(subscription.refresh.status).to eq("unsubscribed")
    expect(subscription.unsubscribed_at).not_to be_nil
  end

  it "rejects invalid unsubscribe links" do
    get "/follow/unsubscribe/1-nope"

    expect(last_response.status).to eq(404)
    expect(last_response.body).to include("Unsubscribe link expired")
  end

  it "schedules follower notifications when an authenticated hiker creates a trip" do
    account = create_account
    WentHiking::Models::HikeFollowSubscription.create(
      followed_account_id: account.id,
      email: "trail@example.com",
      status: "active",
      confirmed_at: Time.now,
      created_at: Time.now,
      updated_at: Time.now
    )
    login_as(account.id)

    post "/hikes", {
      "name" => "Lookout Mountain",
      "hiked_at" => "2026-05-17",
      "nights" => "1",
      "mileage" => "8.5",
      "elevation" => "1700",
      "source_url" => "",
      "lat" => "",
      "lng" => "",
      "report_markdown" => "Clear views."
    }

    trip = WentHiking::Models::Trip.first(name: "Lookout Mountain")
    notification = WentHiking::Models::HikeFollowNotification.first(trip_id: trip.id)

    expect(last_response.status).to eq(302)
    expect(notification).not_to be_nil
    expect(notification.hike_follow_notification_deliveries_dataset.select_map(:email)).to eq(["trail@example.com"])
  end
end
