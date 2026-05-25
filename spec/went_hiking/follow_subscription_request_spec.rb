require_relative "../spec_helper"

require "went_hiking/follow_subscription_request"
require "went_hiking/models"

RSpec.describe WentHiking::FollowSubscriptionRequest do
  before do
    WentHiking::Email.clear_deliveries
  end

  def create_account(name: "Kai", email: "kai@example.com")
    WentHiking::Models::Account.create(email: email, name: name, slug: name.downcase, status_id: 2, created_at: Time.now, updated_at: Time.now)
  end

  it "creates a pending subscription and sends a confirmation email" do
    account = create_account
    result = described_class.new(account: account, email: " HIKER@Example.COM ").call
    subscription = WentHiking::Models::HikeFollowSubscription.first(email: "hiker@example.com")

    expect(result).to be_success
    expect(result).to be_email_sent
    expect(subscription.followed_account_id).to eq(account.id)
    expect(subscription.status).to eq("pending")
    expect(subscription.confirmation_token_digest).not_to be_nil
    expect(WentHiking::Email.deliveries.size).to eq(1)
    expect(WentHiking::Email.deliveries.first.subject).to eq("Follow Kai on Went Hiking")
    expect(WentHiking::Email.deliveries.first.text_body).to include("/follow/confirm/")
  end

  it "does not send another confirmation for active subscriptions" do
    account = create_account
    subscription = WentHiking::Models::HikeFollowSubscription.create(
      followed_account_id: account.id,
      email: "hiker@example.com",
      status: "active",
      confirmed_at: Time.now,
      created_at: Time.now,
      updated_at: Time.now
    )
    result = described_class.new(account: account, email: "hiker@example.com").call

    expect(result).to be_success
    expect(result).not_to be_email_sent
    expect(subscription.refresh.status).to eq("active")
    expect(WentHiking::Email.deliveries).to be_empty
  end

  it "requires a plausible email address" do
    account = create_account

    result = described_class.new(account: account, email: "not-an-email").call

    expect(result).not_to be_success
    expect(result.errors).to eq(["Enter a valid email address."])
    expect(WentHiking::Models::HikeFollowSubscription.count).to eq(0)
  end

  it "silently ignores honeypot submissions" do
    account = create_account
    result = described_class.new(account: account, email: "hiker@example.com", honeypot: "bot co").call

    expect(result).to be_success
    expect(result).not_to be_email_sent
    expect(WentHiking::Models::HikeFollowSubscription.count).to eq(0)
    expect(WentHiking::Email.deliveries).to be_empty
  end

  it "lets unsubscribed addresses opt back in with a new confirmation" do
    account = create_account
    subscription = WentHiking::Models::HikeFollowSubscription.create(
      followed_account_id: account.id,
      email: "hiker@example.com",
      status: "unsubscribed",
      unsubscribed_at: Time.now,
      created_at: Time.now,
      updated_at: Time.now
    )

    result = described_class.new(account: account, email: "hiker@example.com").call

    expect(result).to be_success
    expect(result).to be_email_sent
    expect(subscription.refresh.status).to eq("pending")
    expect(subscription.unsubscribed_at).to be_nil
    expect(subscription.confirmation_token_digest).not_to be_nil
  end
end
