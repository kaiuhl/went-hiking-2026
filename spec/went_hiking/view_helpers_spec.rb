require_relative "../spec_helper"
require_relative "../../server/view_helpers"

RSpec.describe ViewHelpers do
  subject(:helpers) do
    Object.new.extend(described_class)
  end

  describe "#format_number" do
    it "adds thousands separators to large integers" do
      expect(helpers.format_number(1234)).to eq("1,234")
      expect(helpers.format_number(1234567)).to eq("1,234,567")
    end

    it "preserves useful decimal precision with thousands separators" do
      expect(helpers.format_number(73822.2, precision: 1)).to eq("73,822.2")
      expect(helpers.format_number(1200.0, precision: 1)).to eq("1,200")
    end
  end

  describe "#night_count_label" do
    it "pluralizes backpacking nights" do
      expect(helpers.night_count_label(0)).to be_nil
      expect(helpers.night_count_label(1)).to eq("1 night")
      expect(helpers.night_count_label(2)).to eq("2 nights")
    end
  end

  describe "#avatar_url" do
    it "passes through absolute avatar URLs for seeded legacy previews" do
      account = Struct.new(:avatar_file_name).new("http://wenthiking.com/system/avatars/51/medium/P9140528.jpg")

      expect(helpers.avatar_url(account, "thumbnail")).to eq("http://wenthiking.com/system/avatars/51/medium/P9140528.jpg")
    end
  end
end
