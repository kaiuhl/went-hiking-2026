require_relative "../spec_helper"
require "went_hiking/s3_keys"

RSpec.describe WentHiking::S3Keys do
  it "preserves legacy Paperclip-compatible photo keys" do
    expect(described_class.photo_variant_key(photo_id: 32585, style: "large", filename: "image.jpg")).to eq("system/images/32585/large/image.jpg")
  end

  it "normalizes uploaded original keys" do
    expect(described_class.upload_original_key(account_id: 1, photo_id: 2, filename: "my photo!.jpg")).to eq("uploads/photos/1/2/original/my-photo-.jpg")
  end
end
