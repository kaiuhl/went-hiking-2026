require_relative "../../spec_helper"
require "went_hiking/import/transform"

RSpec.describe WentHiking::Import::Transform do
  it "maps legacy photo rows and variants" do
    transform = described_class.new
    row = {
      id: 32585,
      image_file_name: "photo.JPG",
      image_content_type: "image/jpeg",
      image_file_size: 123,
      stats_added: 1,
      created_at: Time.utc(2020, 1, 1),
      updated_at: Time.utc(2020, 1, 2)
    }

    photo = transform.photo(row, account_id: 1, trip_id: 2)
    variants = transform.photo_variants(row)

    expect(photo).to include(legacy_photo_id: 32585, legacy_image_file_name: "photo.JPG", legacy_stats_added: true)
    expect(variants.map { |variant| variant[:style] }).to include("original", "large", "thumbnail")
    expect(variants.find { |variant| variant[:style] == "large" }[:s3_key]).to eq("system/images/32585/large/photo.jpg")
  end
end
