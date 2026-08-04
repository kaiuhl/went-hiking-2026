# frozen_string_literal: true

require_relative "../../spec_helper"
require "went_hiking/places/trail_import"

RSpec.describe WentHiking::Places::TrailImport do
  def segment(name:, admin_org:, miles:, trail_no: "2000", trail_type: "TERRA", coordinates: nil)
    coordinates ||= [[-121.70, 45.30], [-121.71, 45.35], [-121.72, 45.40]]
    {
      "external_id" => "cn-#{admin_org}-#{miles}",
      "name" => name,
      "place_type" => "trail",
      "source_place_type" => "trail",
      "latitude" => nil,
      "longitude" => nil,
      "state_code" => "",
      "aliases" => [],
      "search_rank" => 62,
      "confidence" => 0.8,
      "geometry_json" => {"type" => "LineString", "coordinates" => coordinates},
      "metadata_json" => {
        "trail_no" => trail_no,
        "trail_type" => trail_type,
        "admin_org" => admin_org,
        "gis_miles" => miles
      }
    }
  end

  it "collapses a trail's segments across ranger districts into one place per forest" do
    records = [
      segment(name: "PACIFIC CREST TRAIL", admin_org: "060501", miles: 12.4),
      segment(name: "PACIFIC CREST TRAIL", admin_org: "060502", miles: 30.1,
        coordinates: [[-121.60, 45.00], [-121.62, 45.10], [-121.64, 45.20], [-121.66, 45.28], [-121.68, 45.31]]),
      segment(name: "PACIFIC CREST TRAIL", admin_org: "0510", miles: 8.0)
    ]

    places = described_class.dedupe(records)

    expect(places.length).to eq(2)
    mount_hood = places.find { |place| place.dig("metadata_json", "admin_org") == "0605" }
    expect(mount_hood["name"]).to eq("Pacific Crest Trail")
    expect(mount_hood["external_id"]).to eq("0605-2000")
    expect(mount_hood.dig("metadata_json", "gis_miles")).to eq(42.5)
    # Midpoint vertex of the longest segment, as [lat, lng] columns.
    expect(mount_hood["latitude"]).to eq(45.2)
    expect(mount_hood["longitude"]).to eq(-121.64)
    expect(mount_hood["geometry_json"]).to be_nil
  end

  it "keeps only TERRA trails and drops unnamed or geometry-less segments" do
    records = [
      segment(name: "SKYLINE SNOW ROUTE", admin_org: "0605", miles: 4.0, trail_type: "SNOW"),
      segment(name: "", admin_org: "0605", miles: 2.0),
      segment(name: "BARE TRAIL", admin_org: "0605", miles: 1.0).merge("geometry_json" => nil)
    ]

    expect(described_class.dedupe(records)).to eq([])
  end

  it "drops role-only segment names and demotes modifier names" do
    records = [
      segment(name: "RETURN", admin_org: "0605", miles: 1.0),
      segment(name: "BOUNDARY SPUR", admin_org: "0605", miles: 1.0),
      segment(name: "DOG MOUNTAIN ALTERNATE", admin_org: "0605", miles: 2.0),
      segment(name: "DOG MOUNTAIN TRAIL", admin_org: "0605", miles: 3.0)
    ]

    places = described_class.dedupe(records)

    names = places.to_h { |place| [place["name"], place["search_rank"]] }
    expect(names.keys).to contain_exactly("Dog Mountain Alternate", "Dog Mountain Trail")
    expect(names.fetch("Dog Mountain Alternate")).to eq(described_class::DEMOTED_SEARCH_RANK)
    expect(names.fetch("Dog Mountain Trail")).to eq(62)
  end
end
