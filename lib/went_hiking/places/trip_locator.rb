# frozen_string_literal: true

require_relative "models"
require_relative "geometry"

module WentHiking
  module Places
    # Turns a trip's pin into words: the nearest named place worth naming, and
    # the most specific area containing the pin. Distance thresholds are
    # deliberately tight — an unnamed hike beats a wrong name in someone's
    # byline — and linear features (streams, springs, valleys) are weighted
    # down because GNIS is dense with them and a trip should not be named
    # after the nearest creek when a lake is 300 meters further.
    #
    # Backfill only ever touches rows whose location_source is NULL or
    # auto_*; anything an author set stays theirs.
    class TripLocator
      VERSION = "auto_v1"

      TYPE_WEIGHTS = {
        "trailhead" => 1.3,
        "trail" => 1.05,
        "campground" => 1.15,
        "lake" => 1.1,
        "waterfall" => 1.1,
        "peak" => 1.1,
        "destination" => 1.0,
        "river" => 0.6,
        "stream" => 0.6,
        "valley" => 0.6,
        "spring" => 0.6,
        "canal" => 0.5,
        "swamp" => 0.5,
        "levee" => 0.5
      }.freeze
      DEFAULT_TYPE_WEIGHT = 0.9

      # Degrees of bbox half-width for the candidate fetch (≈5.5 km), widened
      # once when nothing is nearby.
      LAT_WINDOW = 0.05
      LNG_WINDOW = 0.07
      MAX_KM = 2.0
      # Trails are represented by their midpoint, so they earn extra reach.
      MAX_TRAIL_KM = 3.5

      def initialize(now: Time.now)
        @now = now
      end

      # => {place:, distance_km:, area_name:, area_id:} with nil place when
      # nothing is close enough to name.
      def locate(lat, lng)
        best = nearest_place(lat, lng)
        area = containing_area(lat, lng)

        {
          place: best&.fetch(:place),
          distance_km: best&.fetch(:distance_km),
          area_id: area&.fetch(:id),
          area_name: area&.fetch(:name)
        }
      end

      def backfill(dry_run: false, force: false, logger: ->(line) {})
        scope = Models::Trip.exclude(lat: nil).exclude(lng: nil)
        scope = if force
          scope.where(Sequel[location_source: nil] | Sequel.like(:location_source, "auto_%"))
        else
          scope.where(location_source: nil)
        end

        counts = {trips: 0, named: 0, areas: 0}
        scope.each do |trip|
          result = locate(trip.lat, trip.lng)
          counts[:trips] += 1
          counts[:named] += 1 if result[:place]
          counts[:areas] += 1 if result[:area_id]

          place = result[:place]
          distance = result[:distance_km] ? " (#{result[:distance_km].round(2)} km)" : ""
          logger.call("#{trip.slug}: #{place ? place.name + distance : "—"}#{" · #{result[:area_name]}" if result[:area_name]}")
          next if dry_run

          trip.this.update(
            place_id: place&.id,
            location_name: place&.name,
            area_id: result[:area_id],
            area_name: result[:area_name],
            location_source: VERSION,
            location_resolved_at: @now
          )
        end
        counts
      end

      private

      def nearest_place(lat, lng)
        candidates = candidates_near(lat, lng, 1.0)
        candidates = candidates_near(lat, lng, 3.0) if candidates.empty?

        scored = candidates.filter_map do |place|
          distance_km = Geometry.haversine_km(lat, lng, place.latitude, place.longitude)
          limit_km = (place.place_type == "trail") ? MAX_TRAIL_KM : MAX_KM
          next if distance_km > limit_km

          weight = TYPE_WEIGHTS.fetch(place.place_type.to_s, DEFAULT_TYPE_WEIGHT)
          score = weight * (1 + place.search_rank.to_i / 200.0) / (1 + distance_km / 0.75)
          {place: place, distance_km: distance_km, score: score}
        end

        scored.max_by { |entry| entry[:score] }
      end

      def candidates_near(lat, lng, widen)
        lat_window = LAT_WINDOW * widen
        lng_window = LNG_WINDOW * widen
        Place.where(active: true)
          .exclude(latitude: nil)
          .exclude(longitude: nil)
          .where { (latitude >= lat - lat_window) & (latitude <= lat + lat_window) & (longitude >= lng - lng_window) & (longitude <= lng + lng_window) }
          .all
      end

      def containing_area(lat, lng)
        point = Geometry.factory.point(lng, lat)
        containing = area_geometries.select do |entry|
          bounds = entry[:bounds]
          next false unless lng >= bounds[0] && lng <= bounds[2] && lat >= bounds[1] && lat <= bounds[3]

          Geometry.contains_point?(entry[:geometry], point)
        end

        containing.min_by { |entry| entry[:specificity] }
      end

      # Parsed once per locator instance; ~200 PNW boundaries is tens of
      # megabytes, which a batch backfill holds comfortably and a single
      # locate call pays only when actually used.
      def area_geometries
        @area_geometries ||= Area.active.exclude(boundary_json: nil).all.filter_map do |area|
          boundary = area.boundary
          geometry = Geometry.geojson_geometry(boundary)
          bounds = Geometry.bounds_for_geojson(boundary)
          next unless geometry && bounds

          {id: area.id, name: area.name, specificity: area.specificity, geometry: geometry, bounds: bounds}
        end
      end
    end
  end
end
