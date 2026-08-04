# frozen_string_literal: true

require_relative "../../spec_helper"
require "went_hiking/places"

RSpec.describe "WentHiking::Places models" do
  def create_place(name: "Burnt Lake", place_type: "lake", lat: 45.36, lng: -121.79)
    dataset = WentHiking::Places::PlaceDataset.create(
      slug: "spec-dataset",
      name: "Spec Dataset",
      license_name: "Public Domain"
    )
    place = WentHiking::Places::Place.create(
      slug: WentHiking::Places::Normalizer.slugify(name),
      name: name,
      place_type: place_type,
      latitude: lat,
      longitude: lng,
      state_code: "OR",
      source_dataset_id: dataset.id,
      metadata_json: WentHiking::Places::Jsonb.wrap({"county_name" => "Clackamas"})
    )
    WentHiking::Places::PlaceName.create(
      place_id: place.id,
      name: name,
      normalized_name: WentHiking::Places::Normalizer.normalize(name),
      kind: "official",
      weight: 10
    )
    place
  end

  it "round-trips a place with names, metadata, and dataset licensing" do
    place = create_place

    expect(place.reload.metadata).to eq({"county_name" => "Clackamas"})
    expect(place.place_names.map(&:normalized_name)).to eq(["burnt lake"])
    expect(place.source_dataset.license_name).to eq("Public Domain")
    expect(WentHiking::Places::Place.active.count).to eq(1)
  end

  it "links places to areas by containment match" do
    place = create_place
    area = WentHiking::Places::Area.create(
      slug: "mount-hood",
      name: "Mount Hood National Forest",
      area_type: "national_forest",
      agency: "USFS"
    )
    WentHiking::Places::PlaceAreaMatch.create(
      place_id: place.id,
      area_id: area.id,
      relationship: "contains_point",
      match_method: "rgeo_v1",
      confidence: 0.98
    )

    expect(place.place_area_matches.map { |match| match.area.name }).to eq(["Mount Hood National Forest"])
  end

  it "ranks wilderness as more specific than park and forest for bylines" do
    wilderness = WentHiking::Places::Area.new(area_type: "wilderness")
    forest = WentHiking::Places::Area.new(area_type: "national_forest")

    expect(wilderness.specificity).to be < forest.specificity
  end

  it "gives trips dormant place and area associations that wake with the gazetteer" do
    place = create_place
    account_id = WentHiking.db[:accounts].insert(
      email: "hiker@example.test",
      name: "Kai",
      slug: "kai",
      status_id: 2,
      created_at: Time.now,
      updated_at: Time.now
    )
    trip = WentHiking::Models::Trip.create(
      account_id: account_id,
      name: "Burnt Lake loop",
      hiked_at: Time.utc(2026, 7, 4),
      place_id: place.id,
      location_name: place.name,
      location_source: "author"
    )

    expect(trip.reload.place.name).to eq("Burnt Lake")
    expect(trip.location_name).to eq("Burnt Lake")
  end
end
