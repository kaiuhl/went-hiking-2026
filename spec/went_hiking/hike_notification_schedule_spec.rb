require_relative "../spec_helper"

require "went_hiking/hike_notification_schedule"

RSpec.describe WentHiking::HikeNotificationSchedule do
  around do |example|
    old_timezone = ENV["FOLLOW_NOTIFICATION_TIMEZONE"]
    old_hour = ENV["FOLLOW_NOTIFICATION_HOUR"]
    ENV["FOLLOW_NOTIFICATION_TIMEZONE"] = "America/Los_Angeles"
    ENV["FOLLOW_NOTIFICATION_HOUR"] = "8"
    example.run
  ensure
    ENV["FOLLOW_NOTIFICATION_TIMEZONE"] = old_timezone
    ENV["FOLLOW_NOTIFICATION_HOUR"] = old_hour
  end

  it "schedules the next morning in daylight saving time" do
    run_at = described_class.next_morning_after(now: Time.utc(2026, 5, 25, 22, 30, 0))

    expect(run_at).to eq(Time.utc(2026, 5, 26, 15, 0, 0))
  end

  it "schedules the next morning in standard time" do
    run_at = described_class.next_morning_after(now: Time.utc(2026, 1, 10, 22, 30, 0))

    expect(run_at).to eq(Time.utc(2026, 1, 11, 16, 0, 0))
  end
end
