# frozen_string_literal: true

require "tmpdir"
require_relative "../../spec_helper"
require "went_hiking/places/area_refresher"

RSpec.describe WentHiking::Places::AreaRefresher do
  let(:box) do
    {"type" => "Polygon", "coordinates" => [[[-122.0, 45.0], [-121.0, 45.0], [-121.0, 46.0], [-122.0, 46.0], [-122.0, 45.0]]]}
  end

  def write_config(dir)
    path = File.join(dir, "areas.yml")
    File.write(path, YAML.dump({
      "usfs_forests" => {"regions" => ["06"]},
      "wilderness" => {"envelope" => {"min_lat" => 41.9, "max_lat" => 49.1, "min_lon" => -124.9, "max_lon" => -116.4}},
      "nps_units" => [
        {"slug" => "mount-rainier-national-park", "name" => "Mount Rainier National Park", "boundary_source_codes" => ["MORA"], "state_codes" => "wa"}
      ]
    }))
    path
  end

  def stubbed_refresher(dir, nps_features:)
    refresher = described_class.new(config_path: write_config(dir))
    allow(refresher).to receive(:fetch_features) do |url, _params|
      case url
      when described_class::FOREST_URL
        [{"geometry" => box, "properties" => {"forestname" => "Mount Hood National Forest", "region" => "06", "forestnumber" => "06", "gis_acres" => 1_000_000}}]
      when described_class::WILDERNESS_URL
        [
          {"geometry" => box, "properties" => {"wildernessname" => "Mount Hood Wilderness", "gis_acres" => 60_000.4, "areaid" => "1"}},
          {"geometry" => box, "properties" => {"wildernessname" => "Mount Hood Wilderness", "gis_acres" => 100.6, "areaid" => "2"}}
        ]
      when described_class::NPS_URL
        nps_features
      end
    end
    refresher
  end

  let(:mora_feature) do
    {"geometry" => box, "properties" => {"UNIT_CODE" => "MORA", "UNIT_NAME" => "Mount Rainier National Park"}}
  end

  it "upserts forests, merged wilderness, and NPS parks with distinct slugs" do
    Dir.mktmpdir do |dir|
      counts = stubbed_refresher(dir, nps_features: [mora_feature]).refresh
      expect(counts).to eq({areas: 3})

      forest = WentHiking::Places::Area.first(slug: "mount-hood-national-forest")
      wilderness = WentHiking::Places::Area.first(slug: "mount-hood-wilderness")
      park = WentHiking::Places::Area.first(slug: "mount-rainier-national-park")

      expect(forest.area_type).to eq("national_forest")
      expect(wilderness.area_type).to eq("wilderness")
      # Two source features merged into one wilderness, acres summed.
      expect(wilderness.boundary["coordinates"].length).to eq(2)
      expect(wilderness.metadata["gis_acres"]).to eq(60_101)
      expect(park.agency).to eq("NPS")
      expect(park.state_codes).to eq("wa")

      # Refreshing again updates in place rather than duplicating.
      stubbed_refresher(dir, nps_features: [mora_feature]).refresh
      expect(WentHiking::Places::Area.count).to eq(3)
    end
  end

  it "raises when a configured NPS unit has no boundary in the source" do
    Dir.mktmpdir do |dir|
      expect do
        stubbed_refresher(dir, nps_features: []).refresh
      end.to raise_error(/Missing NPS boundaries for mount-rainier-national-park: MORA/)
    end
  end
end
