require_relative "../spec_helper"
require "went_hiking/legacy_urls"

RSpec.describe WentHiking::LegacyUrls do
  it "preserves absolute legacy media URLs" do
    url = "http://wenthiking.com/system/images/43384/large/Alpenhounds_on_Coyote_Wall.jpg"

    expect(described_class.legacy_media_url(url)).to eq(url)
  end
end
