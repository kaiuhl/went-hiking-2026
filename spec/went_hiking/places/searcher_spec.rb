# frozen_string_literal: true

require_relative "../../spec_helper"
require "went_hiking/places"

RSpec.describe WentHiking::Places::Searcher do
  def dataset
    @dataset ||= WentHiking::Places::PlaceDataset.create(slug: "spec-dataset", name: "Spec", license_name: "Public Domain")
  end

  def create_place(name:, place_type:, lat: 45.0, lng: -121.0, state: "or", rank: 30, metadata: {}, slug: nil, aliases: [])
    place = WentHiking::Places::Place.create(
      slug: slug || "spec-#{WentHiking::Places::Normalizer.slugify(name)}-#{rand(100_000)}",
      name: name,
      place_type: place_type,
      latitude: lat,
      longitude: lng,
      state_code: state,
      search_rank: rank,
      source_dataset_id: dataset.id,
      metadata_json: WentHiking::Places::Jsonb.wrap(metadata)
    )
    [name, *aliases].each_with_index do |value, index|
      WentHiking::Places::PlaceName.create(
        place_id: place.id,
        name: value,
        normalized_name: WentHiking::Places::Normalizer.normalize(value),
        kind: index.zero? ? "official" : "alias",
        weight: index.zero? ? 100 : 70
      )
    end
    place
  end

  def create_area(name:, area_type:, slug:, center: nil)
    WentHiking::Places::Area.create(
      slug: slug,
      name: name,
      area_type: area_type,
      agency: "USFS",
      metadata_json: WentHiking::Places::Jsonb.wrap(center ? {"center_lat" => center[0], "center_lon" => center[1]} : {})
    )
  end

  def search(query, limit: 8)
    described_class.new.search(query, limit: limit)
  end

  it "returns exact name matches first, boosted by place type" do
    create_place(name: "Burnt Lake", place_type: "lake")
    create_place(name: "Burnt Lake Creek", place_type: "river")

    results = search("burnt lake")

    expect(results.first[:name]).to eq("Burnt Lake")
    expect(results.map { |result| result[:name] }).to include("Burnt Lake Creek")
  end

  it "resolves leftover query tokens against county context to disambiguate namesakes" do
    create_place(name: "Lost Lake", place_type: "lake", metadata: {"county_name" => "Linn"})
    hood_river = create_place(name: "Lost Lake", place_type: "lake", metadata: {"county_name" => "Hood River"})

    results = search("lost lake hood river")

    expect(results.first[:slug]).to eq(hood_river.slug)
  end

  it "ranks areas above same-named places and matches their short names" do
    create_place(name: "Mount Hood", place_type: "peak")
    create_area(name: "Mt. Hood National Forest", area_type: "national_forest", slug: "mt-hood-national-forest", center: [45.2, -121.7])

    results = search("mount hood")

    expect(results.first[:result_type]).to eq("area")
    expect(results.first[:name]).to eq("Mt. Hood National Forest")
    expect(results.first[:latitude]).to eq(45.2)
    expect(results.map { |result| result[:name] }).to include("Mount Hood")
  end

  it "answers category queries like wilderness and campground" do
    create_area(name: "Goat Rocks Wilderness", area_type: "wilderness", slug: "goat-rocks-wilderness")
    create_place(name: "Riverside Campground", place_type: "campground")

    expect(search("wilderness").first[:name]).to eq("Goat Rocks Wilderness")
    expect(search("campground").first[:name]).to eq("Riverside Campground")
  end

  it "builds a quiet subtitle from type, containing area, and state" do
    area = create_area(name: "Mount Hood National Forest", area_type: "national_forest", slug: "mount-hood-national-forest")
    place = create_place(name: "Ramona Falls", place_type: "waterfall", metadata: {"county_name" => "Clackamas"})
    WentHiking::Places::PlaceAreaMatch.create(place_id: place.id, area_id: area.id, relationship: "contains_point", match_method: "rgeo_v1")

    result = search("ramona falls").first

    expect(result[:subtitle]).to eq("Waterfall · Mount Hood National Forest · Oregon")
    expect(result[:matched_areas]).to eq([{slug: "mount-hood-national-forest", name: "Mount Hood National Forest", area_type: "national_forest"}])
  end

  it "falls back to county when a place has no containing area" do
    create_place(name: "Ramona Falls", place_type: "waterfall", metadata: {"county_name" => "Clackamas"})

    expect(search("ramona falls").first[:subtitle]).to eq("Waterfall · Clackamas County · Oregon")
  end

  it "matches aliases and returns nothing for blank queries" do
    create_place(name: "Wahtum Lake", place_type: "lake", aliases: ["Wahtum Lake Camp"])

    expect(search("lake camp").first[:name]).to eq("Wahtum Lake")
    expect(search("")).to eq([])
    expect(search("   ")).to eq([])
  end
end
