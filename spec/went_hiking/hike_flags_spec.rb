# frozen_string_literal: true

require_relative "../spec_helper"
require "went_hiking/hike_flags"

RSpec.describe WentHiking::HikeFlags do
  it "has a trips column for every flag in the vocabulary" do
    expect(WentHiking.db[:trips].columns).to include(*described_class.keys)
  end

  it "validates tokens against each flag's vocabulary" do
    expect(described_class.valid?(:beauty, "sublime")).to be(true)
    expect(described_class.valid?(:beauty, "meh")).to be(false)
    expect(described_class.valid?("crowds", "solitude")).to be(true)
  end

  it "reads published words for stored tokens and nothing for NULL" do
    expect(described_class.fetch(:swimming).published_for("off_season")).to eq("too cold to swim")
    expect(described_class.fetch(:swimming).published_for(nil)).to be_nil
  end
end
