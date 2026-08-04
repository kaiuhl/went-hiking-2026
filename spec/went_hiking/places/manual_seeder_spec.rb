# frozen_string_literal: true

require "tmpdir"
require_relative "../../spec_helper"
require "went_hiking/places/manual_seeder"

RSpec.describe WentHiking::Places::ManualSeeder do
  def write_config(dir, places)
    path = File.join(dir, "place_manual.yml")
    File.write(path, YAML.dump({
      "dataset" => {"name" => "Curated", "license_name" => "Went Hiking curated"},
      "places" => places
    }))
    path
  end

  let(:burnt_lake) do
    {
      "slug" => "burnt-lake",
      "name" => "Burnt Lake",
      "place_type" => "lake",
      "latitude" => 45.3509,
      "longitude" => -121.8024,
      "state_code" => "or",
      "aliases" => ["Burnt Lake Trail"],
      "search_rank" => 100,
      "confidence" => 0.92
    }
  end

  it "seeds curated places with aliases and deactivates removed entries" do
    Dir.mktmpdir do |dir|
      path = write_config(dir, [burnt_lake, burnt_lake.merge("slug" => "wahtum-lake", "name" => "Wahtum Lake", "aliases" => [])])
      counts = described_class.new(path: path).seed
      expect(counts).to eq({datasets: 1, places: 2, names: 3})

      place = WentHiking::Places::Place.first(slug: "wh-manual-burnt-lake")
      expect(place.search_rank).to eq(100)
      expect(place.place_names.map(&:kind)).to contain_exactly("official", "alias")

      # Removing an entry deactivates it; the row and its id survive.
      described_class.new(path: write_config(dir, [burnt_lake])).seed
      expect(WentHiking::Places::Place.first(slug: "wh-manual-wahtum-lake").active).to be(false)
      expect(place.reload.active).to be(true)
    end
  end

  it "ships a parseable curated config whose entries all carry coordinates" do
    config = YAML.load_file(File.join(WentHiking.root, "config/place_manual.yml"))
    places = config.fetch("places")

    expect(places.length).to be >= 60
    expect(places).to all(include("name", "place_type", "latitude", "longitude", "state_code"))
  end
end
