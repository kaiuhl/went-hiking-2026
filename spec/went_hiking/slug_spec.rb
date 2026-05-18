require_relative "../spec_helper"
require "went_hiking/slug"

RSpec.describe WentHiking::Slug do
  it "generates stable URL-safe slugs" do
    expect(described_class.generate("Mt. Hood & Elk Cove!")).to eq("mt-hood-and-elk-cove")
  end

  it "builds and extracts id slugs" do
    slug = described_class.id_slug(42, "Loowit Trail")

    expect(slug).to eq("42-loowit-trail")
    expect(described_class.extract_id(slug)).to eq(42)
  end
end
