# frozen_string_literal: true

require_relative "models"
require_relative "geometry"

module WentHiking
  module Places
    # Precomputes which area contains each place, so search and bylines never
    # touch geometry at request time. The loop is area-outer: load one
    # boundary, ask Postgres for the places inside its bounding box (served by
    # the [latitude, longitude] index), and run the real point-in-polygon test
    # only on those. Places are points by construction — every importer and
    # the manual seeder set coordinates — so containment is contains_point,
    # nothing more.
    class Resolver
      MATCH_METHOD = "rgeo_v1"

      def initialize(now: Time.now)
        @now = now
      end

      def resolve(dataset_slug: nil)
        dataset = PlaceDataset.first(slug: dataset_slug.to_s) unless dataset_slug.to_s.empty?
        return {area_matches: 0} if dataset_slug.to_s != "" && !dataset

        rows = []
        WentHiking.db.transaction do
          reset_matches(dataset)

          Area.active.exclude(boundary_json: nil).all.each do |area|
            boundary = area.boundary
            geometry = Geometry.geojson_geometry(boundary)
            bounds = Geometry.bounds_for_geojson(boundary)
            next unless geometry && bounds

            candidates_for(dataset, bounds).each do |(place_id, latitude, longitude)|
              point = Geometry.factory.point(longitude, latitude)
              next unless Geometry.contains_point?(geometry, point)

              rows << {
                place_id: place_id,
                area_id: area.id,
                relationship: "contains_point",
                match_method: MATCH_METHOD,
                confidence: 0.98,
                created_at: @now,
                updated_at: @now
              }
            end
          end

          rows.each_slice(1000) { |batch| PlaceAreaMatch.multi_insert(batch) }
        end

        {area_matches: rows.length}
      end

      private

      def reset_matches(dataset)
        if dataset
          PlaceAreaMatch.where(place_id: Place.where(source_dataset_id: dataset.id).select(:id)).delete
        else
          PlaceAreaMatch.dataset.delete
        end
      end

      def candidates_for(dataset, bounds)
        min_lon, min_lat, max_lon, max_lat = bounds
        scope = Place.where(active: true)
          .exclude(latitude: nil)
          .exclude(longitude: nil)
          .where { (latitude >= min_lat) & (latitude <= max_lat) & (longitude >= min_lon) & (longitude <= max_lon) }
        scope = scope.where(source_dataset_id: dataset.id) if dataset
        scope.select_map([:id, :latitude, :longitude])
      end
    end
  end
end
