# frozen_string_literal: true

require_relative "normalizer"
require_relative "geometry"

module WentHiking
  module Places
    # Collapses USFS EDW trail segments into one searchable place per named
    # trail per forest. The layer is centerline segments — the Pacific Crest
    # Trail arrives as hundreds of rows across dozens of admin units — so
    # segments group by (forest, normalized name), sum their miles, and take
    # the midpoint vertex of the longest segment as the representative point:
    # trip pins and photos cluster along a trail, and mid-trail minimizes how
    # far the nearest-place backfill has to reach. Source names arrive
    # UPPERCASE and truncated to 30 characters; only TERRA (dirt) trails
    # survive — SNOW and WATER routes are not hikes.
    module TrailImport
      module_function

      # Words that name a segment's role, not a destination. A trail called
      # nothing but these ("Return", "Boundary Spur", "Traverse") means
      # nothing outside its forest's GIS and is dropped. A real name carrying
      # a modifier ("Dog Mountain Alternate") is kept but demoted so the
      # canonical name wins bylines and search.
      IGNORABLE_NAME_TOKENS = %w[
        access alternate alt boundary bypass climb climbing connector cutoff
        interpretive loop nature return route spur tie trail traverse way
      ].freeze
      MODIFIER_NAME_TOKENS = %w[
        access alternate alt bypass connector cutoff return spur tie traverse
      ].freeze
      DEMOTED_SEARCH_RANK = 45

      def dedupe(records)
        hiking = records.select { |record| record.dig("metadata_json", "trail_type").to_s.casecmp?("TERRA") }
        named = hiking.reject { |record| record["name"].to_s.strip.empty? }

        named.group_by { |record| group_key(record) }.filter_map do |(forest_org, normalized), segments|
          next if normalized.empty?

          tokens = normalized.split
          next if (tokens - IGNORABLE_NAME_TOKENS).empty?

          longest = segments.max_by { |segment| miles(segment) }
          midpoint = midpoint_for(longest["geometry_json"])
          next unless midpoint

          longest.merge(
            "search_rank" => tokens.intersect?(MODIFIER_NAME_TOKENS) ? DEMOTED_SEARCH_RANK : longest["search_rank"],
            "name" => display_name(longest["name"]),
            "external_id" => [forest_org, trail_no(longest)].reject(&:empty?).join("-"),
            "latitude" => midpoint[1],
            "longitude" => midpoint[0],
            "geometry_json" => nil,
            "aliases" => [],
            "metadata_json" => {
              "trail_no" => trail_no(longest),
              "admin_org" => forest_org,
              "gis_miles" => segments.sum { |segment| miles(segment) }.round(1)
            }
          )
        end
      end

      def group_key(record)
        admin_org = record.dig("metadata_json", "admin_org").to_s
        # The first four characters are region + forest; the rest is the
        # ranger district, and one trail routinely crosses several.
        [admin_org[0, 4].to_s, Normalizer.normalize(record["name"])]
      end

      def miles(record)
        record.dig("metadata_json", "gis_miles").to_f
      end

      def trail_no(record)
        record.dig("metadata_json", "trail_no").to_s.strip
      end

      # "PACIFIC CREST TRAIL" → "Pacific Crest Trail".
      def display_name(value)
        value.to_s.strip.downcase.gsub(/\b[a-z]/) { |letter| letter.upcase }
      end

      def midpoint_for(geometry)
        pairs = Geometry.coordinate_pairs(Geometry.coordinates_for(geometry || {}))
        return if pairs.empty?

        pairs[pairs.length / 2]
      end
    end
  end
end
