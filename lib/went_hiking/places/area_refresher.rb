# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "yaml"

require_relative "models"
require_relative "normalizer"
require_relative "geometry"

module WentHiking
  module Places
    # Fetches containing-area boundaries — USFS forests by region, wilderness
    # areas by envelope (the layer has no region attribute), NPS parks by unit
    # code — and upserts them into areas.boundary_json. Areas only ever upsert
    # or deactivate; rows are never deleted, because trips and matches hold
    # foreign keys into them. Reworked from Big Fluffy Puffy's
    # BoundaryRefresher, which wrote a checked-in GeoJSON file instead.
    class AreaRefresher
      CONFIG_PATH = File.join(WentHiking.root, "config/areas.yml")
      FOREST_URL = "https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_ForestSystemBoundaries_01/MapServer/0/query"
      WILDERNESS_URL = "https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_Wilderness_01/MapServer/0/query"
      NPS_URL = "https://services1.arcgis.com/fBc8EJBxQRMcHlei/ArcGIS/rest/services/NPS_Land_Resources_Division_Boundary_and_Tract_Data_Service/FeatureServer/2/query"

      def initialize(config_path: CONFIG_PATH, now: Time.now)
        @config_path = config_path
        @now = now
      end

      def refresh
        counts = {areas: 0}

        WentHiking.db.transaction do
          counts[:areas] += refresh_forests
          counts[:areas] += refresh_wilderness
          counts[:areas] += refresh_nps_units
        end

        counts
      end

      private

      def config
        @config ||= YAML.load_file(@config_path)
      end

      def refresh_forests
        regions = Array(config.dig("usfs_forests", "regions")).map(&:to_s)
        return 0 if regions.empty?

        features = fetch_features(FOREST_URL, {
          "where" => "region IN (#{regions.map { |region| "'#{region}'" }.join(",")})",
          "outFields" => "forestname,region,forestnumber,gis_acres"
        })
        raise "USFS forest boundary query returned no features" if features.empty?

        features.count do |feature|
          name = feature.dig("properties", "forestname").to_s.strip
          next false if name.empty?

          upsert_area(
            slug: area_slug(name),
            name: name,
            area_type: "national_forest",
            agency: "USFS",
            region_code: feature.dig("properties", "region"),
            boundary: feature["geometry"],
            source_url: FOREST_URL,
            metadata: {
              "forest_number" => feature.dig("properties", "forestnumber"),
              "gis_acres" => feature.dig("properties", "gis_acres")
            }
          )
          true
        end
      end

      def refresh_wilderness
        envelope = config.dig("wilderness", "envelope")
        return 0 unless envelope

        geometry_param = [
          envelope.fetch("min_lon"), envelope.fetch("min_lat"),
          envelope.fetch("max_lon"), envelope.fetch("max_lat")
        ].join(",")
        features = fetch_features(WILDERNESS_URL, {
          "where" => "1=1",
          "geometry" => geometry_param,
          "geometryType" => "esriGeometryEnvelope",
          "inSR" => "4326",
          "spatialRel" => "esriSpatialRelIntersects",
          "outFields" => "wildernessname,gis_acres,areaid"
        })
        raise "Wilderness boundary query returned no features" if features.empty?

        # One wilderness occasionally arrives as several features; merge them
        # under one name so containment sees a single area.
        features.group_by { |feature| feature.dig("properties", "wildernessname").to_s.strip }.count do |name, group|
          next false if name.empty?

          upsert_area(
            slug: area_slug(name),
            name: name,
            area_type: "wilderness",
            agency: "USFS",
            region_code: nil,
            boundary: combined_geometry(group),
            source_url: WILDERNESS_URL,
            metadata: {
              "gis_acres" => group.sum { |feature| feature.dig("properties", "gis_acres").to_f }.round,
              "area_ids" => group.map { |feature| feature.dig("properties", "areaid") }.compact
            }
          )
          true
        end
      end

      def refresh_nps_units
        units = Array(config["nps_units"])
        return 0 if units.empty?

        codes = units.flat_map { |unit| Array(unit["boundary_source_codes"]).map(&:to_s) }.uniq
        features = fetch_features(NPS_URL, {
          "where" => "UNIT_CODE IN (#{codes.map { |code| "'#{code}'" }.join(",")})",
          "outFields" => "UNIT_CODE,UNIT_NAME,UNIT_TYPE,STATE"
        })
        features_by_code = features.group_by { |feature| feature.dig("properties", "UNIT_CODE").to_s }

        units.count do |unit|
          unit_codes = Array(unit["boundary_source_codes"]).map(&:to_s)
          matched = unit_codes.flat_map { |code| features_by_code.fetch(code, []) }
          missing = unit_codes - matched.map { |feature| feature.dig("properties", "UNIT_CODE").to_s }.uniq
          raise "Missing NPS boundaries for #{unit.fetch("slug")}: #{missing.join(", ")}" unless missing.empty?

          upsert_area(
            slug: unit.fetch("slug"),
            name: unit.fetch("name"),
            area_type: "national_park",
            agency: "NPS",
            region_code: nil,
            state_codes: unit["state_codes"],
            boundary: combined_geometry(matched),
            source_url: NPS_URL,
            metadata: {"nps_unit_codes" => unit_codes}
          )
          true
        end
      end

      def upsert_area(slug:, name:, area_type:, agency:, region_code:, boundary:, source_url:, metadata: {}, state_codes: nil)
        # Search results fly the map somewhere; precomputing the centroid here
        # spares every keystroke from parsing a megabyte of boundary.
        center = Geometry.center_for(boundary)
        metadata = metadata.merge("center_lat" => center&.first, "center_lon" => center&.last).compact

        area = Area.first(slug: slug) || Area.new(slug: slug, created_at: @now)
        area.set(
          name: name,
          area_type: area_type,
          agency: agency,
          region_code: region_code,
          state_codes: state_codes,
          boundary_json: Jsonb.wrap(boundary),
          boundary_source_url: source_url,
          boundary_updated_at: @now,
          active: true,
          metadata_json: Jsonb.wrap(metadata),
          updated_at: @now
        )
        area.save
        area
      end

      # Unlike place slugs, area slugs keep their designators — the forest and
      # the wilderness that share a mountain's name must not share a slug.
      def area_slug(name)
        Normalizer.normalize(name).split.join("-")
      end

      def fetch_features(url, params)
        features = []
        offset = 0
        loop do
          uri = URI(url)
          uri.query = URI.encode_www_form(params.merge(
            "f" => "geojson",
            "outSR" => "4326",
            "returnGeometry" => "true",
            "geometryPrecision" => "4",
            "resultRecordCount" => "100",
            "resultOffset" => offset.to_s
          ))
          response = Net::HTTP.get_response(uri)
          raise "Area boundary request failed for #{url}: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

          payload = JSON.parse(response.body)
          raise "Area boundary request failed for #{url}: #{payload["error"].inspect}" if payload["error"]

          page = payload.fetch("features", [])
          features.concat(page)
          break if page.empty? || !exceeded_transfer_limit?(payload)

          offset += page.length
        end
        features
      end

      def exceeded_transfer_limit?(payload)
        payload["exceededTransferLimit"] || payload.dig("properties", "exceededTransferLimit")
      end

      def combined_geometry(features)
        polygons = features.flat_map do |feature|
          geometry = feature.fetch("geometry", {})
          case geometry["type"]
          when "Polygon"
            [geometry.fetch("coordinates")]
          when "MultiPolygon"
            geometry.fetch("coordinates")
          else
            []
          end
        end

        {"type" => "MultiPolygon", "coordinates" => polygons}
      end
    end
  end
end
