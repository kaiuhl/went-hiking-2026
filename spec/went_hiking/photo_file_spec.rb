require_relative "../spec_helper"

require "went_hiking/photo_file"

RSpec.describe WentHiking::PhotoFile do
  describe ".stored_filename" do
    it "keeps the uploader's stem and takes the extension from the content type" do
      expect(described_class.stored_filename("lake view.JPG", "image/jpeg")).to eq("lake-view.jpg")
      expect(described_class.stored_filename("ridge.png", "image/png")).to eq("ridge.png")
      expect(described_class.stored_filename("loop.gif", "image/gif")).to eq("loop.gif")
    end

    it "refuses a client-chosen extension that would be served as active content" do
      expect(described_class.stored_filename("payload.svg", "image/jpeg")).to eq("payload.jpg")
      expect(described_class.stored_filename("payload.html", "image/png")).to eq("payload.png")
      expect(described_class.stored_filename("payload.svg.jpg.svg", "image/jpeg")).to eq("payload.svg.jpg.jpg")
    end

    it "strips directories and anything that could climb out of a key" do
      expect(described_class.stored_filename("../../etc/passwd", "image/jpeg")).to eq("passwd.jpg")
      expect(described_class.stored_filename("a/b/c/lake.svg", "image/jpeg")).to eq("lake.jpg")
    end

    it "falls back to a name when there is nothing usable to keep" do
      expect(described_class.stored_filename("", "image/jpeg")).to eq("photo.jpg")
      expect(described_class.stored_filename(".svg", "image/jpeg")).to eq("svg.jpg")
      expect(described_class.stored_filename("...", "image/jpeg")).to eq("photo.jpg")
    end

    it "stores an unnameable type under an inert extension" do
      expect(described_class.stored_filename("payload.svg", "image/svg+xml")).to eq("payload.bin")
    end
  end
end
