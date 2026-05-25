require_relative "../spec_helper"

require "went_hiking/hike_notification_job"
require "went_hiking/hike_notification_scheduler"
require "went_hiking/models"

RSpec.describe WentHiking::HikeNotificationJob do
  before do
    WentHiking::Email.clear_deliveries
  end

  def create_account(name: "Kai", email: "kai@example.com")
    WentHiking::Models::Account.create(email: email, name: name, slug: name.downcase, status_id: 2, created_at: Time.now, updated_at: Time.now)
  end

  def create_subscription(account, email: "hiker@example.com", status: "active")
    WentHiking::Models::HikeFollowSubscription.create(
      followed_account_id: account.id,
      email: email,
      status: status,
      confirmed_at: (Time.now if status == "active"),
      created_at: Time.now,
      updated_at: Time.now
    )
  end

  def create_trip(account)
    WentHiking::Models::Trip.create(
      account_id: account.id,
      name: "Burnt Lake",
      slug: "burnt-lake",
      nights: 1,
      mileage: 8.5,
      elevation: 1700,
      hiked_at: Time.utc(2026, 5, 25),
      report_markdown: "Original draft.",
      created_at: Time.now,
      updated_at: Time.now
    )
  end

  it "sends the edited hike content and marks deliveries sent" do
    account = create_account
    create_subscription(account)
    trip = create_trip(account)
    notification = WentHiking::HikeNotificationScheduler.schedule_trip(trip)
    trip.update(name: "Burnt Lake Updated", report_markdown: "Final story with **photos**.", updated_at: Time.now)
    described_class.allocate.run(notification.id)
    delivery = notification.refresh.hike_follow_notification_deliveries_dataset.first

    expect(WentHiking::Email.deliveries.size).to eq(1)
    expect(WentHiking::Email.deliveries.first.subject).to eq("Kai posted a new hike: Burnt Lake Updated")
    expect(WentHiking::Email.deliveries.first.text_body).to include("Final story with photos")
    expect(WentHiking::Email.deliveries.first.text_body).to include("/follow/unsubscribe/")
    expect(delivery.status).to eq("sent")
    expect(delivery.sent_at).not_to be_nil
    expect(notification.sent_at).not_to be_nil
  end

  it "skips followers who unsubscribe before the scheduled send" do
    account = create_account
    subscription = create_subscription(account)
    trip = create_trip(account)
    notification = WentHiking::HikeNotificationScheduler.schedule_trip(trip)
    subscription.update(status: "unsubscribed", unsubscribed_at: Time.now, updated_at: Time.now)
    described_class.allocate.run(notification.id)
    delivery = notification.refresh.hike_follow_notification_deliveries_dataset.first

    expect(WentHiking::Email.deliveries).to be_empty
    expect(delivery.status).to eq("skipped")
  end

  it "does not resend deliveries that already succeeded" do
    account = create_account
    create_subscription(account)
    trip = create_trip(account)
    notification = WentHiking::HikeNotificationScheduler.schedule_trip(trip)

    described_class.allocate.run(notification.id)
    described_class.allocate.run(notification.id)

    expect(WentHiking::Email.deliveries.size).to eq(1)
  end

  it "records delivery errors and leaves failed deliveries pending for retry" do
    account = create_account
    create_subscription(account)
    trip = create_trip(account)
    notification = WentHiking::HikeNotificationScheduler.schedule_trip(trip)
    allow(WentHiking::Email).to receive(:deliver).and_raise(StandardError, "SES unavailable")

    expect { described_class.allocate.run(notification.id) }.to raise_error(StandardError, "SES unavailable")
    delivery = notification.refresh.hike_follow_notification_deliveries_dataset.first

    expect(delivery.status).to eq("pending")
    expect(delivery.last_error).to include("SES unavailable")
    expect(notification.sent_at).to be_nil
  end
end
