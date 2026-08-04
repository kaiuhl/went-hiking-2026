# frozen_string_literal: true

require_relative "../../spec_helper"
require "went_hiking/places"

RSpec.describe WentHiking::Places::TripLocator do
  def dataset
    @dataset ||= WentHiking::Places::PlaceDataset.create(slug: "spec-dataset", name: "Spec", license_name: "Public Domain")
  end

  def create_place(name:, place_type:, lat:, lng:, rank: 30)
    WentHiking::Places::Place.create(
      slug: "spec-#{WentHiking::Places::Normalizer.slugify(name)}",
      name: name,
      place_type: place_type,
      latitude: lat,
      longitude: lng,
      search_rank: rank,
      source_dataset_id: dataset.id
    )
  end

  def create_area
    WentHiking::Places::Area.create(
      slug: "mount-hood-wilderness",
      name: "Mount Hood Wilderness",
      area_type: "wilderness",
      boundary_json: WentHiking::Places::Jsonb.wrap({
        "type" => "Polygon",
        "coordinates" => [[[-122.0, 45.0], [-121.0, 45.0], [-121.0, 46.0], [-122.0, 46.0], [-122.0, 45.0]]]
      })
    )
  end

  def create_trip(name:, lat:, lng:, location_source: nil, location_name: nil)
    account_id = WentHiking.db[:accounts].insert(
      email: "#{name.downcase.tr(" ", "-")}@example.test", name: name, slug: name.downcase.tr(" ", "-"),
      status_id: 2, created_at: Time.now, updated_at: Time.now
    )
    WentHiking::Models::Trip.create(
      account_id: account_id, name: name, hiked_at: Time.utc(2026, 7, 4),
      lat: lat, lng: lng, location_source: location_source, location_name: location_name
    )
  end

  it "names a pin after the best nearby place, not merely the nearest creek" do
    create_place(name: "Nearby Creek", place_type: "river", lat: 45.3620, lng: -121.7900)
    lake = create_place(name: "Burnt Lake", place_type: "lake", lat: 45.3560, lng: -121.7900)

    result = described_class.new.locate(45.3600, -121.7900)

    expect(result[:place].id).to eq(lake.id)
    expect(result[:distance_km]).to be < 1.0
  end

  it "leaves the name blank when nothing is close enough, but still finds the area" do
    create_place(name: "Far Lake", place_type: "lake", lat: 45.60, lng: -121.79)
    create_area

    result = described_class.new.locate(45.36, -121.79)

    expect(result[:place]).to be_nil
    expect(result[:area_name]).to eq("Mount Hood Wilderness")
  end

  it "gives trails midpoint slack that point features do not get" do
    create_place(name: "Timberline Trail", place_type: "trail", lat: 45.331, lng: -121.711)

    # ~3 km from the trail midpoint: inside trail reach, outside point reach.
    result = described_class.new.locate(45.331, -121.750)

    expect(result[:place].name).to eq("Timberline Trail")
  end

  describe "#backfill" do
    it "writes snapshots for unresolved trips and never touches author rows" do
      create_place(name: "Burnt Lake", place_type: "lake", lat: 45.3560, lng: -121.7900)
      create_area
      trip = create_trip(name: "Burnt Lake loop", lat: 45.3600, lng: -121.7900)
      authored = create_trip(name: "Secret spot", lat: 45.3600, lng: -121.7910, location_source: "author", location_name: "My Secret Name")

      counts = described_class.new.backfill

      expect(counts).to eq({trips: 1, named: 1, areas: 1})
      trip.reload
      expect(trip.location_name).to eq("Burnt Lake")
      expect(trip.area_name).to eq("Mount Hood Wilderness")
      expect(trip.location_source).to eq("auto_v1")
      expect(trip.location_resolved_at).not_to be_nil
      expect(authored.reload.location_name).to eq("My Secret Name")
    end

    it "re-touches auto rows only under force, and writes nothing on a dry run" do
      place = create_place(name: "Burnt Lake", place_type: "lake", lat: 45.3560, lng: -121.7900)
      trip = create_trip(name: "Burnt Lake loop", lat: 45.3600, lng: -121.7900)

      lines = []
      described_class.new.backfill(dry_run: true, logger: ->(line) { lines << line })
      expect(trip.reload.location_name).to be_nil
      expect(lines.join).to include("Burnt Lake")

      described_class.new.backfill
      place.update(name: "Renamed Lake")
      described_class.new.backfill
      expect(trip.reload.location_name).to eq("Burnt Lake")

      described_class.new.backfill(force: true)
      expect(trip.reload.location_name).to eq("Renamed Lake")
    end
  end
end
