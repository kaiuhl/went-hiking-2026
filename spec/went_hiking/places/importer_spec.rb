# frozen_string_literal: true

require "tmpdir"
require "zip"
require_relative "../../spec_helper"
require "went_hiking/places/importer"

RSpec.describe WentHiking::Places::Importer do
  let(:gnis_mapping) do
    {
      "external_id" => %w[feature_id FEATURE_ID],
      "name" => %w[feature_name FEATURE_NAME],
      "place_type" => %w[feature_class FEATURE_CLASS],
      "latitude" => %w[prim_lat_dec PRIM_LAT_DEC],
      "longitude" => %w[prim_long_dec PRIM_LONG_DEC],
      "state_code" => %w[state_alpha STATE_ALPHA],
      "state_name" => %w[state_name STATE_NAME],
      "aliases" => %w[variant_name VARIANT_NAME],
      "search_rank" => 30,
      "search_rank_map" => {"Basin" => 48, "Lake" => 56, "Summit" => 50},
      "place_type_map" => {"Basin" => "destination", "Lake" => "lake", "Summit" => "peak"},
      "metadata_fields" => {
        "county_name" => "county_name",
        "map_name" => "map_name",
        "source_feature_class" => "feature_class"
      },
      "confidence" => 0.82
    }
  end
  let(:gnis_config) do
    {
      "slug" => "gnis",
      "name" => "USGS GNIS",
      "license_name" => "Public Domain",
      "enabled" => true,
      "format" => "zip",
      "zip_glob" => "**/*.txt",
      "col_sep" => "|",
      "feature_class_filter" => %w[Basin Lake Summit],
      "mapping" => gnis_mapping
    }
  end

  def write_gnis_zip(dir)
    zip_path = File.join(dir, "DomesticNames_OR_Text.zip")
    Zip::File.open(zip_path, create: true) do |zip|
      zip.get_output_stream("Text/DomesticNames_OR.txt") { |io| io.write(gnis_fixture) }
    end
    zip_path
  end

  it "parses modern GNIS pipe-delimited text from state ZIP downloads" do
    Dir.mktmpdir do |dir|
      zip_path = write_gnis_zip(dir)

      records = described_class.new.send(:records_from_path, zip_path, gnis_config)

      expect(records.map { |record| record.fetch("name") }).to contain_exactly(
        "Eight Lakes Basin",
        "Jorn Lake",
        "Green Peak Lake"
      )
      expect(records.map { |record| [record["name"], record["place_type"], record["state_code"]] }).to include(
        ["Eight Lakes Basin", "destination", "or"],
        ["Jorn Lake", "lake", "or"],
        ["Green Peak Lake", "lake", "or"]
      )
      jorn = records.find { |record| record["name"] == "Jorn Lake" }
      expect(jorn.fetch("search_rank")).to eq(56)
      expect(jorn.fetch("aliases")).to eq(["Jorn Pond"])
      expect(jorn.fetch("metadata_json")).to include(
        "county_name" => "Linn",
        "map_name" => "Marion Lake",
        "source_feature_class" => "Lake"
      )
    end
  end

  it "imports a dataset into Postgres with bulk upserts, idempotently" do
    Dir.mktmpdir do |dir|
      zip_path = write_gnis_zip(dir)
      config_path = File.join(dir, "place_datasets.yml")
      File.write(config_path, YAML.dump({"datasets" => [gnis_config.merge("paths" => [zip_path])]}))
      importer = described_class.new(path: config_path, cache_dir: dir)

      first = importer.import
      expect(first).to eq({datasets: 1, places: 3, names: 4, deactivated: 0})
      expect(WentHiking::Places::Place.count).to eq(3)
      expect(WentHiking::Places::PlaceName.count).to eq(4)

      jorn = WentHiking::Places::Place.first(name: "Jorn Lake")
      expect(jorn.slug).to eq("gnis-jorn-lake-1144402")
      expect(jorn.place_names.map(&:kind)).to contain_exactly("official", "alias")
      expect(jorn.source_dataset.license_name).to eq("Public Domain")

      # A deactivated place reactivates on reimport, and nothing duplicates.
      jorn.update(active: false)
      second = importer.import
      expect(second[:places]).to eq(3)
      expect(WentHiking::Places::Place.count).to eq(3)
      expect(WentHiking::Places::PlaceName.count).to eq(4)
      expect(jorn.reload.active).to be(true)

      # A place the source no longer carries deactivates rather than lingers.
      gone = WentHiking::Places::Place.create(
        slug: "gnis-gone-lake-999", name: "Gone Lake", place_type: "lake",
        source_dataset_id: jorn.source_dataset_id, updated_at: Time.now - 3600
      )
      third = importer.import
      expect(third[:deactivated]).to eq(1)
      expect(gone.reload.active).to be(false)
    end
  end

  it "clips records to configured bounds instead of a hardcoded launch box" do
    Dir.mktmpdir do |dir|
      zip_path = write_gnis_zip(dir)
      bounded = gnis_config.merge(
        "paths" => [zip_path],
        "bounds" => {"min_lat" => 44.5205, "max_lat" => 44.521, "min_lon" => -121.87, "max_lon" => -121.86}
      )
      config_path = File.join(dir, "place_datasets.yml")
      File.write(config_path, YAML.dump({"datasets" => [bounded]}))

      described_class.new(path: config_path, cache_dir: dir).import

      expect(WentHiking::Places::Place.select_map(:name)).to contain_exactly("Eight Lakes Basin")
    end
  end

  it "uses stable cache filenames for query URLs" do
    basename = described_class.new.send(
      :cache_basename,
      {"slug" => "usfs-trails", "format" => "geojson"},
      "https://example.test/arcgis/rest/services/Trails/MapServer/0/query?f=geojson&where=1%3D1",
      "query"
    )

    expect(basename).to match(/\Ausfs-trails-[0-9a-f]{12}\.geojson\z/)
  end

  it "refuses truncated ArcGIS GeoJSON unless the dataset pages" do
    payload = JSON.generate(
      "type" => "FeatureCollection",
      "features" => [],
      "properties" => {"exceededTransferLimit" => true}
    )
    config = {"slug" => "usfs-trails", "mapping" => {"name" => "trail_name"}}

    expect do
      described_class.new.send(:geojson_records_from_string, payload, config)
    end.to raise_error(/exceeded transfer limit/)

    expect(
      described_class.new.send(:geojson_records_from_string, payload, config.merge("arcgis_paged" => true))
    ).to eq([])
  end

  def gnis_fixture
    <<~TXT
      feature_id|feature_name|feature_class|state_name|county_name|map_name|prim_lat_dec|prim_long_dec|variant_name
      1141701|Eight Lakes Basin|Basin|Oregon|Linn|Marion Lake|44.5206747|-121.863397|
      1144402|Jorn Lake|Lake|Oregon|Linn|Marion Lake|44.516724|-121.8662648|Jorn Pond
      1121392|Green Peak Lake|Lake|Oregon|Linn|Marion Forks|44.5209529|-121.8889535|
      123|Administrative School|School|Oregon|Linn|Marion Lake|44.1|-121.1|
    TXT
  end
end
