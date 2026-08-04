# frozen_string_literal: true

require "rgeo"

module WentHiking
  module Places
    module Geometry
      EARTH_RADIUS_KM = 6371.0

      module_function

      def factory
        @factory ||= RGeo::Geos.factory
      end

      def haversine_km(lat1, lng1, lat2, lng2)
        d_lat = radians(lat2 - lat1)
        d_lng = radians(lng2 - lng1)
        a = Math.sin(d_lat / 2)**2 +
          Math.cos(radians(lat1)) * Math.cos(radians(lat2)) * Math.sin(d_lng / 2)**2
        2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(a))
      end

      def radians(degrees)
        degrees * Math::PI / 180.0
      end

      def geojson_geometry(value)
        value = value.to_hash if value.respond_to?(:to_hash)
        return unless value.is_a?(Hash)

        geometry = value["geometry"] || value[:geometry] if (value["type"] || value[:type]).to_s == "Feature"
        geometry ||= value

        case type_for(geometry)
        when "Point"
          coordinate = coordinates_for(geometry)
          factory.point(coordinate[0].to_f, coordinate[1].to_f)
        when "LineString"
          factory.line_string(coordinates_for(geometry).map { |lon, lat| factory.point(lon.to_f, lat.to_f) })
        when "MultiLineString"
          factory.multi_line_string(
            coordinates_for(geometry).map do |line|
              factory.line_string(line.map { |lon, lat| factory.point(lon.to_f, lat.to_f) })
            end
          )
        when "Polygon"
          validate_geometry(polygon_from_coordinates(coordinates_for(geometry)))
        when "MultiPolygon"
          polygons = coordinates_for(geometry).filter_map { |polygon| polygon_from_coordinates(polygon) }
          validate_geometry(factory.multi_polygon(polygons)) unless polygons.empty?
        end
      rescue RGeo::Error::InvalidGeometry, NoMethodError, TypeError
        nil
      end

      def point_for(place)
        return factory.point(place.longitude.to_f, place.latitude.to_f) if place.longitude && place.latitude

        geometry = geojson_geometry(place.geometry)
        return unless geometry

        geometry.respond_to?(:centroid) ? geometry.centroid : nil
      rescue RGeo::Error::InvalidGeometry
        nil
      end

      def center_for(geojson)
        geometry = geojson_geometry(geojson)
        return unless geometry

        point = geometry.respond_to?(:centroid) ? geometry.centroid : geometry
        # A repaired geometry can come back as a collection, which has no
        # coordinates of its own — no center is better than a crash.
        return unless point.respond_to?(:x) && point.respond_to?(:y)

        [point.y.to_f, point.x.to_f]
      rescue RGeo::Error::InvalidGeometry
        nil
      end

      def bounds_for_geojson(value)
        value = value.to_hash if value.respond_to?(:to_hash)
        return unless value.is_a?(Hash)

        geometry = value["geometry"] || value[:geometry] if (value["type"] || value[:type]).to_s == "Feature"
        geometry ||= value

        pairs = coordinate_pairs(coordinates_for(geometry))
        return if pairs.empty?

        longitudes = pairs.map(&:first)
        latitudes = pairs.map(&:last)
        [longitudes.min, latitudes.min, longitudes.max, latitudes.max]
      end

      def bounds_for_place(place)
        if place.longitude && place.latitude
          lon = place.longitude.to_f
          lat = place.latitude.to_f
          return [lon, lat, lon, lat]
        end

        bounds_for_geojson(place.geometry)
      end

      def bounds_intersect?(left, right)
        return true unless left && right

        left[0] <= right[2] &&
          left[2] >= right[0] &&
          left[1] <= right[3] &&
          left[3] >= right[1]
      end

      def intersects?(left, right)
        left && right && left.intersects?(right)
      rescue RGeo::Error::InvalidGeometry, NoMethodError
        false
      end

      def contains_point?(geometry, point)
        geometry && point && geometry.contains?(point)
      rescue RGeo::Error::InvalidGeometry, NoMethodError
        false
      end

      def type_for(geometry)
        geometry["type"] || geometry[:type]
      end

      def coordinates_for(geometry)
        geometry["coordinates"] || geometry[:coordinates]
      end

      def coordinate_pairs(coordinates)
        return [] unless coordinates.is_a?(Array)
        return [[coordinates[0].to_f, coordinates[1].to_f]] if coordinate_pair?(coordinates)

        coordinates.flat_map { |child| coordinate_pairs(child) }
      end

      def coordinate_pair?(coordinates)
        coordinates.length >= 2 &&
          coordinates[0].is_a?(Numeric) &&
          coordinates[1].is_a?(Numeric)
      end

      def polygon_from_coordinates(coordinates)
        return unless coordinates&.first

        exterior = linear_ring(coordinates.first)
        return unless exterior

        holes = coordinates.drop(1).filter_map { |ring| linear_ring(ring) }
        factory.polygon(exterior, holes)
      rescue RGeo::Error::InvalidGeometry
        nil
      end

      def linear_ring(coordinates)
        return unless coordinates

        points = coordinates.map { |lon, lat| factory.point(lon.to_f, lat.to_f) }
        points << points.first unless points.empty? || points.first == points.last
        return if points.length < 4 || points.map { |point| [point.x, point.y] }.uniq.length < 3

        factory.linear_ring(points)
      rescue RGeo::Error::InvalidGeometry
        nil
      end

      def validate_geometry(geometry)
        return unless geometry
        return geometry if geometry.valid?

        geometry.make_valid
      rescue RGeo::Error::InvalidGeometry, RGeo::Error::UnsupportedOperation
        geometry
      end
    end
  end
end
