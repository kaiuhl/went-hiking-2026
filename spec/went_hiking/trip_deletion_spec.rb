require_relative "../spec_helper"
require "went_hiking/models"
require "went_hiking/storage"
require "went_hiking/trip_deletion"

RSpec.describe WentHiking::TripDeletion do
  def create_trip_with_variants(keys)
    account_id = WentHiking.db[:accounts].insert(email: "kai@example.com", name: "Kai", slug: "kai", status_id: 2, created_at: Time.now, updated_at: Time.now)
    trip_id = WentHiking.db[:trips].insert(account_id: account_id, name: "Burnt Lake", slug: "burnt-lake", nights: 0, hiked_at: Time.utc(2026, 5, 1), created_at: Time.now, updated_at: Time.now)
    photo_id = WentHiking.db[:photos].insert(account_id: account_id, trip_id: trip_id, legacy_image_file_name: "lake.jpg", created_at: Time.now, updated_at: Time.now)

    keys.each_with_index do |key, index|
      WentHiking.db[:photo_variants].insert(photo_id: photo_id, style: "style-#{index}", filename: "lake.jpg", s3_key: key, created_at: Time.now, updated_at: Time.now)
    end

    WentHiking::Models::Trip[trip_id]
  end

  # A double rather than a real bucket: what matters is that S3 is asked at all,
  # since the old guard skipped every backend that was not local.
  def fake_s3(deleted, failing: [])
    instance_double(WentHiking::Storage::S3).tap do |storage|
      allow(storage).to receive(:local?).and_return(false)
      allow(storage).to receive(:delete) do |key|
        raise Aws::S3::Errors::AccessDenied.new(nil, "denied") if failing.include?(key)

        deleted << key
      end
    end
  end

  it "deletes stored objects on S3, not just on local disk" do
    keys = ["system/images/1/original/lake.jpg", "system/images/1/large/lake.jpg"]
    trip = create_trip_with_variants(keys)
    deleted = []
    allow(WentHiking::Storage).to receive(:current).and_return(fake_s3(deleted))

    described_class.call(trip)

    expect(deleted).to match_array(keys)
    expect(WentHiking::Models::Trip[trip.id]).to be_nil
  end

  it "skips variants with no stored key" do
    trip = create_trip_with_variants(["system/images/1/original/lake.jpg", ""])
    deleted = []
    allow(WentHiking::Storage).to receive(:current).and_return(fake_s3(deleted))

    described_class.call(trip)

    expect(deleted).to eq(["system/images/1/original/lake.jpg"])
  end

  it "still deletes the trip when the bucket refuses an object" do
    keys = ["system/images/1/original/lake.jpg", "system/images/1/large/lake.jpg"]
    trip = create_trip_with_variants(keys)
    deleted = []
    allow(WentHiking::Storage).to receive(:current).and_return(fake_s3(deleted, failing: [keys.first]))
    allow(described_class).to receive(:warn)

    described_class.call(trip)

    expect(deleted).to eq([keys.last])
    expect(described_class).to have_received(:warn).with(/could not delete stored object #{Regexp.escape(keys.first)}/)
    expect(WentHiking::Models::Trip[trip.id]).to be_nil
    expect(WentHiking.db[:photos].where(trip_id: trip.id).count).to eq(0)
  end

  it "asks the storage backend once for the whole trip" do
    trip = create_trip_with_variants(["system/images/1/original/lake.jpg"])
    allow(WentHiking::Storage).to receive(:current).and_return(fake_s3([]))

    described_class.call(trip)

    expect(WentHiking::Storage).to have_received(:current).once
  end
end
