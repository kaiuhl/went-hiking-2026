# frozen_string_literal: true

require "csv"
require "digest"
require "fileutils"
require "json"
require "net/http"
require "time"
require "uri"
require "yaml"
require "zip"

require_relative "models"
require_relative "normalizer"
require_relative "states"
require_relative "trail_import"

module WentHiking
  module Places
    # Declarative dataset importer, ported from Big Fluffy Puffy and rebuilt
    # in three places for national scale: sources stream one file (or ArcGIS
    # page) at a time instead of concatenating every state into one array;
    # rows land in bulk INSERT ... ON CONFLICT batches instead of a
    # SELECT-then-save per record; and layers marked arcgis_paged follow
    # exceededTransferLimit/resultOffset until the layer runs dry. Coverage
    # is config, not code — a dataset may carry `bounds:`, and going national
    # is deleting those four lines of YAML.
    #
    # Downloads cache in tmp/place_imports and are never re-fetched while the
    # file exists; `rm -rf tmp/place_imports` is the refresh knob.
    class Importer
      CONFIG_PATH = File.join(WentHiking.root, "config/place_datasets.yml")
      CACHE_DIR = File.join(WentHiking.root, "tmp/place_imports")
      BATCH_SIZE = 2000
      CACHE_EXTENSIONS = {
        "csv" => ".csv",
        "geojson" => ".geojson",
        "json" => ".json",
        "tsv" => ".tsv",
        "txt" => ".txt",
        "zip" => ".zip"
      }.freeze

      PLACE_UPDATE = {
        name: Sequel[:excluded][:name],
        place_type: Sequel[:excluded][:place_type],
        latitude: Sequel[:excluded][:latitude],
        longitude: Sequel[:excluded][:longitude],
        geometry_json: Sequel[:excluded][:geometry_json],
        metadata_json: Sequel[:excluded][:metadata_json],
        state_code: Sequel[:excluded][:state_code],
        source_dataset_id: Sequel[:excluded][:source_dataset_id],
        source_external_id: Sequel[:excluded][:source_external_id],
        source_url: Sequel[:excluded][:source_url],
        confidence: Sequel[:excluded][:confidence],
        search_rank: Sequel[:excluded][:search_rank],
        active: true,
        updated_at: Sequel[:excluded][:updated_at]
      }.freeze

      NAME_UPDATE = {
        name: Sequel[:excluded][:name],
        kind: Sequel[:excluded][:kind],
        weight: Sequel[:excluded][:weight],
        updated_at: Sequel[:excluded][:updated_at]
      }.freeze

      def initialize(path: CONFIG_PATH, cache_dir: CACHE_DIR)
        @path = path
        @cache_dir = cache_dir
      end

      def import(dataset_slugs: nil)
        config = YAML.load_file(@path)
        counts = {datasets: 0, places: 0, names: 0, deactivated: 0}
        selected_slugs = Array(dataset_slugs).compact.map(&:to_s)

        Array(config.fetch("datasets")).each do |dataset_config|
          next unless selected_slugs.empty? || selected_slugs.include?(dataset_config.fetch("slug"))

          WentHiking.db.transaction do
            dataset = upsert_dataset(dataset_config)
            counts[:datasets] += 1
            import_dataset(dataset, dataset_config, counts) if dataset_config.fetch("enabled", false)
          end
        end

        counts
      end

      private

      def import_dataset(dataset, config, counts)
        started_at = Time.now

        if (transform = config["transform"])
          # A transform needs the dataset whole — trail segments group across
          # page boundaries — so this path trades streaming for correctness.
          records = []
          each_source_records(config) { |batch| records.concat(batch) }
          upsert_batch(dataset, config, apply_transform(transform, records), counts)
        else
          each_source_records(config) do |batch|
            upsert_batch(dataset, config, batch, counts)
          end
        end

        # Anything this run didn't touch left the source; deactivate rather
        # than delete, so trips pointing at it keep their snapshots.
        counts[:deactivated] += Place
          .where(source_dataset_id: dataset.id, active: true)
          .where { updated_at < started_at }
          .update(active: false, updated_at: Time.now)
      end

      def apply_transform(transform, records)
        case transform
        when "trail_dedupe"
          TrailImport.dedupe(records)
        else
          raise "Unknown place import transform: #{transform}"
        end
      end

      def each_source_records(config)
        source_paths(config).each do |source_path|
          next unless File.file?(source_path)

          records = records_from_path(source_path, config)
          yield records unless records.empty?
        end
      end

      def upsert_dataset(config)
        now = Time.now
        dataset = PlaceDataset.first(slug: config.fetch("slug")) || PlaceDataset.new(slug: config.fetch("slug"), created_at: now)
        dataset.set(
          name: config.fetch("name"),
          source_url: config["source_url"],
          license_name: config.fetch("license_name"),
          license_url: config["license_url"],
          attribution_text: config["attribution_text"],
          retrieved_at: parse_time(config["retrieved_at"]) || now,
          metadata_json: Jsonb.wrap(config["metadata_json"] || {}),
          updated_at: now
        )
        dataset.save
        dataset
      end

      def upsert_batch(dataset, config, records, counts)
        records = records.select { |record| in_bounds?(record, config["bounds"]) }
        return if records.empty?

        now = Time.now
        records_by_slug = {}
        records.each { |record| records_by_slug[place_slug(dataset, record)] = record }

        records_by_slug.keys.each_slice(BATCH_SIZE) do |slugs|
          rows = slugs.map { |slug| place_row(dataset, config, records_by_slug.fetch(slug), slug, now) }
          WentHiking.db[:places].insert_conflict(target: :slug, update: PLACE_UPDATE).multi_insert(rows)
          ids_by_slug = WentHiking.db[:places].where(slug: slugs).select_hash(:slug, :id)

          name_rows = {}
          slugs.each do |slug|
            record = records_by_slug.fetch(slug)
            place_id = ids_by_slug.fetch(slug)
            official = record.fetch("name").to_s.strip
            names_for(record).each do |name|
              normalized = Normalizer.normalize(name)
              next if normalized.empty?

              name_rows[[place_id, normalized]] ||= {
                place_id: place_id,
                name: name,
                normalized_name: normalized,
                kind: (name == official) ? "official" : "alias",
                weight: (name == official) ? 100 : 70,
                created_at: now,
                updated_at: now
              }
            end
          end
          WentHiking.db[:place_names]
            .insert_conflict(target: [:place_id, :normalized_name], update: NAME_UPDATE)
            .multi_insert(name_rows.values)

          counts[:places] += rows.length
          counts[:names] += name_rows.length
        end
      end

      def place_row(dataset, config, record, slug, now)
        {
          slug: slug,
          name: record.fetch("name").to_s.strip,
          place_type: normalized_place_type(record["place_type"]),
          latitude: record["latitude"],
          longitude: record["longitude"],
          geometry_json: Jsonb.wrap(record["geometry_json"]),
          metadata_json: Jsonb.wrap(record["metadata_json"] || {}),
          state_code: record["state_code"].to_s.downcase,
          source_dataset_id: dataset.id,
          source_external_id: record["external_id"]&.to_s,
          source_url: record["source_url"] || config["source_url"],
          confidence: record["confidence"].to_f,
          search_rank: record["search_rank"].to_i,
          active: true,
          created_at: now,
          updated_at: now
        }
      end

      def records_from_path(source_path, config)
        case format_for(source_path, config)
        when "zip"
          zip_records(source_path, config)
        when "geojson", "json"
          geojson_records(source_path, config)
        when "csv"
          delimited_records(source_path, config, col_sep: ",")
        when "tsv", "txt"
          delimited_records(source_path, config, col_sep: col_sep_for(config))
        else
          []
        end
      end

      def source_paths(config)
        configured_paths = (Array(config["paths"]) + Array(config["path"])).reject { |path| path.to_s.empty? }
        local_paths = configured_paths.map { |path| File.expand_path(path, WentHiking.root) }
        data_urls = (Array(config["data_urls"]) + Array(config["data_url"])).reject { |url| url.to_s.empty? }

        local_paths + data_urls.flat_map do |data_url|
          config["arcgis_paged"] ? paged_source_paths(config, data_url) : [download_source(config, data_url)]
        end
      end

      # Follows ArcGIS resultOffset paging until a page comes back without
      # exceededTransferLimit. Each page caches as its own file (the offset is
      # part of the URL digest), so a re-run replays from disk.
      def paged_source_paths(config, data_url)
        paths = []
        offset = 0
        loop do
          path = download_source(config, "#{data_url}&resultOffset=#{offset}")
          payload = JSON.parse(File.read(path))
          if payload["error"]
            File.delete(path)
            raise "Place import failed for #{config.fetch("slug")}: ArcGIS error #{payload["error"].inspect}"
          end

          paths << path
          features = payload.fetch("features", [])
          break if features.empty? || !exceeded_transfer_limit?(payload)

          offset += features.length
        end
        paths
      end

      def download_source(config, data_url)
        FileUtils.mkdir_p(@cache_dir)
        uri = URI.parse(data_url)
        basename = File.basename(uri.path)
        basename = cache_basename(config, data_url, basename) if basename.empty? || uri.query.to_s != "" || File.extname(basename).empty?
        target = File.join(@cache_dir, basename)
        return target if File.file?(target)

        response = Net::HTTP.get_response(URI(data_url))
        raise "Place import failed for #{data_url}: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        File.binwrite(target, response.body)
        target
      end

      def cache_basename(config, data_url, basename)
        extension = CACHE_EXTENSIONS[config["format"].to_s] || File.extname(URI.parse(data_url).path)
        extension = ".dat" if extension.to_s.empty?
        slug = config.fetch("slug")
        digest = Digest::SHA1.hexdigest(data_url)[0, 12]
        stem = File.extname(basename).empty? ? slug : File.basename(basename, File.extname(basename))

        "#{stem}-#{digest}#{extension}"
      end

      def zip_records(path, config)
        Zip::File.open(path) do |zip_file|
          zip_file.glob(config.fetch("zip_glob", "*")).flat_map do |entry|
            next [] if entry.directory?

            content = entry.get_input_stream.read.force_encoding(Encoding::UTF_8)
            case format_for(entry.name, config, inside_zip: true)
            when "csv"
              delimited_records_from_string(content, config, col_sep: ",")
            when "tsv", "txt"
              delimited_records_from_string(content, config, col_sep: col_sep_for(config))
            when "geojson", "json"
              geojson_records_from_string(content, config)
            else
              []
            end
          end
        end
      end

      def geojson_records(path, config)
        geojson_records_from_string(File.read(path), config)
      end

      def geojson_records_from_string(content, config)
        payload = JSON.parse(content)
        if exceeded_transfer_limit?(payload) && !config["arcgis_paged"]
          raise "Place import failed for #{config.fetch("slug")}: GeoJSON source exceeded transfer limit (mark the dataset arcgis_paged)."
        end

        features = payload.fetch("features", [])
        mapping = config.fetch("mapping", {})
        features.filter_map do |feature|
          properties = feature.fetch("properties", {})
          record = record_from_properties(properties, mapping).merge(
            "geometry_json" => feature["geometry"],
            "latitude" => point_latitude(feature["geometry"], properties, mapping),
            "longitude" => point_longitude(feature["geometry"], properties, mapping)
          )
          record_allowed?(record, config) ? record : nil
        end
      end

      def exceeded_transfer_limit?(payload)
        payload["exceededTransferLimit"] || payload.dig("properties", "exceededTransferLimit")
      end

      def delimited_records(path, config, col_sep:)
        delimited_records_from_string(File.read(path, mode: "r:bom|utf-8"), config, col_sep: col_sep)
      end

      def delimited_records_from_string(content, config, col_sep:)
        mapping = config.fetch("mapping", {})
        CSV.parse(content, headers: true, col_sep: col_sep).filter_map do |row|
          record = record_from_properties(normalized_properties(row.to_h), mapping)
          record_allowed?(record, config) ? record : nil
        end
      end

      def record_from_properties(properties, mapping)
        place_type = value_at(properties, mapping["place_type"]) || mapping["default_place_type"] || "place"
        state_code = value_at(properties, mapping["state_code"])
        state_code = States.code_for(value_at(properties, mapping["state_name"])) if state_code.to_s.empty?

        {
          "external_id" => value_at(properties, mapping["external_id"]),
          "name" => value_at(properties, mapping.fetch("name")),
          "place_type" => mapped_place_type(place_type, mapping),
          "source_place_type" => place_type,
          "latitude" => numeric(value_at(properties, mapping["latitude"])),
          "longitude" => numeric(value_at(properties, mapping["longitude"])),
          "state_code" => state_code.to_s.downcase,
          "source_url" => value_at(properties, mapping["source_url"]),
          "aliases" => split_aliases(value_at(properties, mapping["aliases"])),
          "search_rank" => search_rank_for(place_type, mapping),
          "confidence" => Float(mapping.fetch("confidence", 0.7)),
          "metadata_json" => metadata_for(properties, mapping)
        }
      end

      def names_for(record)
        [record.fetch("name"), *Array(record["aliases"])].compact.map(&:to_s).map(&:strip).reject(&:empty?)
      end

      def in_bounds?(record, bounds)
        return true unless bounds

        lat = record["latitude"].to_f
        lon = record["longitude"].to_f
        return true if lat.zero? && lon.zero? && record["geometry_json"]

        lat.between?(Float(bounds.fetch("min_lat")), Float(bounds.fetch("max_lat"))) &&
          lon.between?(Float(bounds.fetch("min_lon")), Float(bounds.fetch("max_lon")))
      end

      def place_slug(dataset, record)
        base = Normalizer.slugify(record.fetch("name"))
        suffix = record["external_id"].to_s.strip
        suffix = Digest::SHA1.hexdigest("#{dataset.slug}:#{record.fetch("name")}:#{record["latitude"]}:#{record["longitude"]}")[0, 8] if suffix.empty?

        "#{dataset.slug}-#{base}-#{Normalizer.slugify(suffix)}".squeeze("-")
      end

      def normalized_place_type(value)
        value.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
      end

      def value_at(properties, key)
        Array(key).each do |candidate|
          next if candidate.to_s.empty?

          value = properties[candidate] || properties[candidate.to_s] || properties[candidate.to_sym]
          return value unless value.to_s.empty?
        end

        nil
      end

      def split_aliases(value)
        value.to_s.split(/[|;]/).map(&:strip).reject(&:empty?)
      end

      def numeric(value)
        return if value.to_s.strip.empty?

        Float(value)
      rescue ArgumentError
        nil
      end

      def parse_time(value)
        return if value.to_s.empty?

        Time.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def point_latitude(geometry, properties, mapping)
        numeric(value_at(properties, mapping["latitude"])) || ((geometry&.fetch("type", nil) == "Point") ? geometry["coordinates"][1].to_f : nil)
      end

      def point_longitude(geometry, properties, mapping)
        numeric(value_at(properties, mapping["longitude"])) || ((geometry&.fetch("type", nil) == "Point") ? geometry["coordinates"][0].to_f : nil)
      end

      def format_for(path, config, inside_zip: false)
        return "zip" if File.extname(path).downcase == ".zip" && !inside_zip

        configured_format = config["format"].to_s
        return configured_format if configured_format != "" && !(inside_zip && configured_format == "zip")

        File.extname(path).downcase.delete_prefix(".")
      end

      def col_sep_for(config)
        separator = config.fetch("col_sep", "\t")
        (separator == "\\t") ? "\t" : separator
      end

      def mapped_place_type(place_type, mapping)
        place_type_map = mapping.fetch("place_type_map", {})
        place_type_map.fetch(place_type.to_s, place_type)
      end

      def search_rank_for(place_type, mapping)
        search_rank_map = mapping.fetch("search_rank_map", {})
        Integer(search_rank_map.fetch(place_type.to_s, mapping.fetch("search_rank", 0)))
      end

      def record_allowed?(record, config)
        feature_class_filter = Array(config["feature_class_filter"]).map(&:to_s)
        return true if feature_class_filter.empty?

        feature_class_filter.include?(record["source_place_type"].to_s)
      end

      def metadata_for(properties, mapping)
        mapping.fetch("metadata_fields", {}).filter_map do |key, source|
          value = value_at(properties, source)
          next if value.to_s.empty?

          [key, value]
        end.to_h
      end

      def normalized_properties(properties)
        properties.to_h.transform_keys do |key|
          key.to_s.encode("UTF-8", invalid: :replace, undef: :replace).delete_prefix("\uFEFF")
        end
      end
    end
  end
end
