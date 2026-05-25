require_relative "../spec_helper"

require "went_hiking/hike_notification_scheduler"
require "went_hiking/models"

RSpec.describe WentHiking::HikeNotificationScheduler do
  def create_account(name:, email:)
    WentHiking::Models::Account.create(email: email, name: name, slug: name.downcase, status_id: 2, created_at: Time.now, updated_at: Time.now)
  end

  def create_trip(account)
    WentHiking::Models::Trip.create(account_id: account.id, name: "Burnt Lake", slug: "burnt-lake", nights: 0, hiked_at: Time.utc(2026, 5, 25), created_at: Time.now, updated_at: Time.now)
  end

  def create_subscription(account, email:, status:)
    WentHiking::Models::HikeFollowSubscription.create(
      followed_account_id: account.id,
      email: email,
      status: status,
      confirmed_at: (Time.now if status == "active"),
      created_at: Time.now,
      updated_at: Time.now
    )
  end

  it "snapshots active followers when a hike is created" do
    account = create_account(name: "Kai", email: "kai@example.com")
    other = create_account(name: "Other", email: "other@example.com")
    active = create_subscription(account, email: "active@example.com", status: "active")
    create_subscription(account, email: "pending@example.com", status: "pending")
    create_subscription(other, email: "other-follower@example.com", status: "active")
    trip = create_trip(account)

    notification = described_class.schedule_trip(trip, now: Time.utc(2026, 5, 25, 20, 0, 0))
    deliveries = notification.hike_follow_notification_deliveries_dataset.all

    expect(notification.trip_id).to eq(trip.id)
    expect(notification.account_id).to eq(account.id)
    expect(notification.scheduled_at.strftime("%Y-%m-%d %H:%M:%S")).to eq("2026-05-26 15:00:00")
    expect(deliveries.map(&:subscription_id)).to eq([active.id])
    expect(deliveries.map(&:email)).to eq(["active@example.com"])
  end

  it "does not create notifications when there are no active followers" do
    account = create_account(name: "Kai", email: "kai@example.com")
    create_subscription(account, email: "pending@example.com", status: "pending")
    trip = create_trip(account)

    expect(described_class.schedule_trip(trip)).to be_nil
    expect(WentHiking::Models::HikeFollowNotification.count).to eq(0)
  end

  it "does not add followers who subscribe after the hike is scheduled" do
    account = create_account(name: "Kai", email: "kai@example.com")
    create_subscription(account, email: "first@example.com", status: "active")
    trip = create_trip(account)

    notification = described_class.schedule_trip(trip)
    create_subscription(account, email: "late@example.com", status: "active")

    expect(notification.refresh.hike_follow_notification_deliveries_dataset.select_map(:email)).to eq(["first@example.com"])
  end
end
