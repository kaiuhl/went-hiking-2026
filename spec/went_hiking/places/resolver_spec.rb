# frozen_string_literal: true

require_relative "../../spec_helper"
require "went_hiking/places/resolver"

RSpec.describe WentHiking::Places::Resolver do
  def create_dataset(slug: "spec-dataset")
    WentHiking::Places::PlaceDataset.create(slug: slug, name: "Spec", license_name: "Public Domain")
  end

  def create_place(dataset, name:, lat:, lng:)
    WentHiking::Places::Place.create(
      slug: "#{dataset.slug}-#{WentHiking::Places::Normalizer.slugify(name)}",
      name: name,
      place_type: "lake",
      latitude: lat,
      longitude: lng,
      source_dataset_id: dataset.id
    )
  end

  # A one-degree box around Mount Hood-ish coordinates.
  def create_area(slug: "mount-hood-national-forest", name: "Mount Hood National Forest", area_type: "national_forest")
    WentHiking::Places::Area.create(
      slug: slug,
      name: name,
      area_type: area_type,
      agency: "USFS",
      boundary_json: WentHiking::Places::Jsonb.wrap({
        "type" => "Polygon",
        "coordinates" => [[[-122.2, 45.0], [-121.2, 45.0], [-121.2, 46.0], [-122.2, 46.0], [-122.2, 45.0]]]
      })
    )
  end

  it "matches places inside an area boundary and skips those outside" do
    dataset = create_dataset
    inside = create_place(dataset, name: "Burnt Lake", lat: 45.36, lng: -121.79)
    create_place(dataset, name: "Waldo Lake", lat: 43.73, lng: -122.04)
    area = create_area

    counts = described_class.new.resolve

    expect(counts).to eq({area_matches: 1})
    match = WentHiking::Places::PlaceAreaMatch.first
    expect(match.place_id).to eq(inside.id)
    expect(match.area_id).to eq(area.id)
    expect(match.relationship).to eq("contains_point")
  end

  it "rebuilds matches idempotently and scopes to one dataset when asked" do
    dataset = create_dataset
    other = create_dataset(slug: "other-dataset")
    create_place(dataset, name: "Burnt Lake", lat: 45.36, lng: -121.79)
    other_place = create_place(other, name: "Mirror Lake", lat: 45.30, lng: -121.79)
    create_area

    described_class.new.resolve
    expect(WentHiking::Places::PlaceAreaMatch.count).to eq(2)

    # A scoped resolve rebuilds only that dataset's matches.
    other_place.update(latitude: 10.0, longitude: 10.0)
    counts = described_class.new.resolve(dataset_slug: "other-dataset")
    expect(counts).to eq({area_matches: 0})
    expect(WentHiking::Places::PlaceAreaMatch.count).to eq(1)

    expect(described_class.new.resolve(dataset_slug: "missing")).to eq({area_matches: 0})
    expect(WentHiking::Places::PlaceAreaMatch.count).to eq(1)
  end

  it "ignores areas without boundaries and places without coordinates" do
    dataset = create_dataset
    create_place(dataset, name: "Nowhere Lake", lat: nil, lng: nil)
    WentHiking::Places::Area.create(slug: "boundaryless", name: "Boundaryless", area_type: "wilderness")

    expect(described_class.new.resolve).to eq({area_matches: 0})
  end
end
