# frozen_string_literal: true

require "yaml"

require_relative "models"
require_relative "normalizer"
require_relative "geometry"

module WentHiking
  module Places
    # Seeds the hand-curated destinations from config/place_manual.yml — the
    # names people actually search for, ranked above the raw gazetteer so
    # "Burnt Lake" finds the lake before its eleven GNIS namesakes. Entries
    # removed from the YAML deactivate rather than delete, so trips keep
    # their foreign keys.
    class ManualSeeder
      CONFIG_PATH = File.join(WentHiking.root, "config/place_manual.yml")
      DATASET_SLUG = "wh-manual"

      def initialize(path: CONFIG_PATH, now: Time.now)
        @path = path
        @now = now
      end

      def seed
        counts = {datasets: 0, places: 0, names: 0}

        WentHiking.db.transaction do
          dataset = upsert_dataset(manual_dataset_config)
          counts[:datasets] += 1
          place_ids = []

          Array(manual_config.fetch("places", [])).each do |config|
            place = upsert_place(dataset, config)
            place_ids << place.id
            counts[:places] += 1
            counts[:names] += upsert_names(place, names_for(config)).length
          end
          deactivate_stale_places(dataset, place_ids)
        end

        counts
      end

      private

      def manual_config
        @manual_config ||= File.file?(@path) ? YAML.load_file(@path) : {"places" => []}
      end

      def manual_dataset_config
        manual_config.fetch("dataset", {}).merge(
          "slug" => DATASET_SLUG,
          "name" => manual_config.dig("dataset", "name") || "Went Hiking curated destinations",
          "license_name" => manual_config.dig("dataset", "license_name") || "Went Hiking curated",
          "attribution_text" => manual_config.dig("dataset", "attribution_text") || "Curated by Went Hiking."
        )
      end

      def upsert_dataset(config)
        dataset = PlaceDataset.first(slug: config.fetch("slug")) || PlaceDataset.new(slug: config.fetch("slug"), created_at: @now)
        dataset.set(
          name: config.fetch("name"),
          source_url: config["source_url"],
          license_name: config.fetch("license_name"),
          license_url: config["license_url"],
          attribution_text: config["attribution_text"],
          retrieved_at: @now,
          metadata_json: Jsonb.wrap(config["metadata_json"] || {}),
          updated_at: @now
        )
        dataset.save
        dataset
      end

      def upsert_place(dataset, config)
        slug = config["slug"].to_s.strip
        slug = Normalizer.slugify(config.fetch("name")) if slug.empty?
        slug = "#{dataset.slug}-#{slug}"
        place = Place.first(slug: slug) || Place.new(slug: slug, created_at: @now)
        geometry = config["geometry_json"]
        center = Geometry.center_for(geometry)
        place.set(
          name: config.fetch("name"),
          place_type: config.fetch("place_type", "destination"),
          latitude: config["latitude"] || center&.first,
          longitude: config["longitude"] || center&.last,
          geometry_json: Jsonb.wrap(geometry),
          metadata_json: Jsonb.wrap(config["metadata_json"] || {}),
          state_code: config["state_code"],
          source_dataset_id: dataset.id,
          source_external_id: config["source_external_id"],
          source_url: config["source_url"] || dataset.source_url,
          confidence: config.fetch("confidence", 0.9),
          search_rank: config.fetch("search_rank", 80),
          active: config.fetch("active", true),
          updated_at: @now
        )
        place.save
        place
      end

      def upsert_names(place, names)
        names.uniq.filter_map do |name|
          normalized = Normalizer.normalize(name)
          next if normalized.empty?

          record = PlaceName.first(place_id: place.id, normalized_name: normalized) ||
            PlaceName.new(place_id: place.id, normalized_name: normalized, created_at: @now)
          record.set(
            name: name,
            kind: (name == place.name) ? "official" : "alias",
            weight: (name == place.name) ? 100 : 75,
            updated_at: @now
          )
          record.save
        end
      end

      def deactivate_stale_places(dataset, active_ids)
        stale = Place.where(source_dataset_id: dataset.id)
        stale = stale.exclude(id: active_ids) unless active_ids.empty?
        stale.update(active: false, updated_at: @now)
      end

      def names_for(config)
        [config.fetch("name"), *Array(config["aliases"])].compact.map(&:to_s).map(&:strip).reject(&:empty?)
      end
    end
  end
end
