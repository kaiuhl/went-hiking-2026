# frozen_string_literal: true

require_relative "models"
require_relative "normalizer"
require_relative "states"

module WentHiking
  module Places
    # Name → place lookup: an ILIKE candidate fetch over the trigram-indexed
    # place_names (the whole query plus every 2- and 3-token window), then a
    # Ruby scorer. The scorer is what makes the eleventh "Lost Lake" findable:
    # leftover query tokens resolve against county/quad/state/forest context,
    # so "lost lake hood river" beats the ten Lost Lakes somewhere else.
    # Areas (forests, wilderness, parks) search separately and outrank
    # same-named destinations. Ported from Big Fluffy Puffy; area queries
    # select narrow columns because boundary_json rows are megabytes.
    class Searcher
      TYPE_BOOSTS = {
        "trailhead" => 80,
        "campground" => 74,
        "recreation_site" => 68,
        "trail" => 62,
        "lake" => 58,
        "waterfall" => 56,
        "peak" => 54,
        "river" => 52,
        "destination" => 48
      }.freeze

      AREA_RESULT_BOOST = 2400
      AREA_TYPE_BOOSTS = {
        "national_forest" => 130,
        "national_park" => 120,
        "wilderness" => 110
      }.freeze
      AREA_CATEGORY_ALIASES = {
        "area" => %w[national_forest national_park wilderness],
        "areas" => %w[national_forest national_park wilderness],
        "forest" => %w[national_forest],
        "forests" => %w[national_forest],
        "national forest" => %w[national_forest],
        "national forests" => %w[national_forest],
        "national park" => %w[national_park],
        "national parks" => %w[national_park],
        "park" => %w[national_park],
        "parks" => %w[national_park],
        "wilderness" => %w[wilderness],
        "wilderness area" => %w[wilderness],
        "wilderness areas" => %w[wilderness]
      }.freeze
      AREA_GENERIC_QUERY_TOKENS = %w[forest lake national park wilderness area].freeze
      AREA_DESIGNATORS = /\b(national forest|national park|national grassland|wilderness|forest|park)\b/

      CATEGORY_TYPE_ALIASES = {
        "campground" => %w[campground],
        "camping" => %w[campground],
        "campsite" => %w[campground],
        "campsites" => %w[campground],
        "destination" => %w[destination],
        "lake" => %w[lake],
        "peak" => %w[peak],
        "river" => %w[river],
        "trail" => %w[trail],
        "trailhead" => %w[trailhead],
        "waterfall" => %w[waterfall]
      }.freeze

      AREA_COLUMNS = [:id, :slug, :name, :area_type, :state_codes, :metadata_json].freeze

      def search(query, limit: 8)
        normalized_query = Normalizer.normalize(query)
        return [] if normalized_query.empty?

        category_types = category_place_types(normalized_query)
        area_suggestions = matching_area_suggestions(normalized_query)
        place_suggestions = matching_place_suggestions(normalized_query, category_types)

        # GNIS carries points named after the areas themselves; when the area
        # already answers, its gazetteer shadow is noise.
        area_names = area_suggestions.map { |suggestion| Normalizer.normalize(suggestion[:name]) }
        place_suggestions = place_suggestions.reject { |suggestion| area_names.include?(Normalizer.normalize(suggestion[:name])) }

        (area_suggestions + place_suggestions)
          .sort_by { |suggestion| [-suggestion[:score].to_i, result_type_order(suggestion), suggestion[:name].to_s] }
          .first(limit)
      rescue Sequel::DatabaseError
        []
      end

      private

      def matching_place_suggestions(normalized_query, category_types)
        name_rows = matching_name_rows(normalized_query, category_types)
        grouped = name_rows.group_by(&:place_id)
        places_by_id = Place.where(id: grouped.keys).all.to_h { |place| [place.id, place] }
        areas_by_place_id = matched_areas_for(grouped.keys)

        grouped.filter_map do |place_id, rows|
          place = places_by_id[place_id]
          next unless place&.active

          areas = areas_by_place_id.fetch(place_id, [])
          best_name = rows.max_by { |row| score_name(row, place, normalized_query) }
          suggestion_for(place, best_name, score_name(best_name, place, normalized_query), normalized_query, category_types, areas)
        end
      end

      def matching_name_rows(normalized_query, category_types)
        tokens = normalized_query.split
        dataset = PlaceName
          .join(:places, id: :place_id)
          .where(Sequel[:places][:active] => true)

        token_filter = candidate_name_phrases(tokens, normalized_query).reduce(nil) do |filter, phrase|
          expression = Sequel.ilike(Sequel[:place_names][:normalized_name], "%#{phrase}%")
          filter ? (filter | expression) : expression
        end

        category_filter = category_types.any? ? Sequel.expr(Sequel[:places][:place_type] => category_types) : nil
        filter = [token_filter, category_filter].compact.reduce { |left, right| left | right }

        return [] unless filter

        dataset
          .where(filter)
          .select_all(:place_names)
          .order(
            Sequel.desc(Sequel[:places][:search_rank]),
            Sequel.desc(Sequel[:place_names][:weight]),
            Sequel[:place_names][:name]
          )
          .limit(360)
          .all
      end

      def candidate_name_phrases(tokens, normalized_query)
        return [normalized_query] if tokens.length < 2

        phrases = [normalized_query]
        max_window = [tokens.length, 3].min
        max_window.downto(2) do |window_size|
          tokens.each_cons(window_size) { |phrase_tokens| phrases << phrase_tokens.join(" ") }
        end
        phrases.uniq
      end

      # One query for every candidate's containing areas, most specific first —
      # the alternative is a query per candidate place, 360 deep, per keystroke.
      def matched_areas_for(place_ids)
        return {} if place_ids.empty?

        PlaceAreaMatch
          .join(:areas, id: :area_id)
          .where(place_id: place_ids, Sequel[:areas][:active] => true)
          .select(Sequel[:place_area_matches][:place_id], Sequel[:areas][:slug], Sequel[:areas][:name], Sequel[:areas][:area_type])
          .all
          .group_by { |row| row[:place_id] }
          .transform_values do |rows|
            rows
              .map { |row| {slug: row[:slug], name: row[:name], area_type: row[:area_type]} }
              .sort_by { |area| Area::TYPES_BY_SPECIFICITY.index(area[:area_type]) || Area::TYPES_BY_SPECIFICITY.length }
          end
      end

      def suggestion_for(place, name_row, score, normalized_query, category_types, areas)
        {
          result_type: "place",
          id: place.id,
          slug: place.slug,
          name: place.name,
          place_type: place.place_type,
          subtitle: subtitle_for(place, areas),
          latitude: place.latitude,
          longitude: place.longitude,
          matched_areas: areas,
          match_name: name_row.name,
          match_type: match_type_for(place, name_row.normalized_name, normalized_query, category_types),
          score: score +
            type_query_score(place, category_types) +
            context_score(areas) +
            context_query_score(normalized_query, name_row.normalized_name, place, areas)
        }
      end

      def matching_area_suggestions(normalized_query)
        Area.active.select(*AREA_COLUMNS).all.filter_map { |area| area_suggestion_for(area, normalized_query) }
      end

      def area_suggestion_for(area, normalized_query)
        category_match = area_category_match?(area, normalized_query)
        candidates = area_search_names(area)
        best_candidate = candidates.max_by { |candidate| score_area_name(candidate.fetch(:normalized_name), area, normalized_query) }
        return unless best_candidate

        normalized_name = best_candidate.fetch(:normalized_name)
        name_match = area_name_matches_query?(normalized_name, normalized_query)
        return unless category_match || name_match

        score = score_area_name(normalized_name, area, normalized_query)
        score += 760 if category_match

        {
          result_type: "area",
          id: nil,
          slug: area.slug,
          name: area.name,
          place_type: area.area_type,
          subtitle: area_subtitle_for(area),
          latitude: area.metadata["center_lat"],
          longitude: area.metadata["center_lon"],
          matched_areas: [{slug: area.slug, name: area.name, area_type: area.area_type}],
          match_name: area.name,
          match_type: category_match ? "place_type" : match_type(normalized_name, normalized_query),
          score: score
        }
      end

      def area_search_names(area)
        raw_names = [
          area.name,
          area.slug.to_s.tr("-", " "),
          area_short_name(area.name)
        ]

        raw_names
          .map { |name| name.to_s.strip }
          .reject(&:empty?)
          .uniq
          .map { |name| {name: name, normalized_name: Normalizer.normalize(name)} }
          .reject { |candidate| candidate.fetch(:normalized_name).empty? }
      end

      def area_short_name(value)
        Normalizer
          .normalize(value)
          .gsub(AREA_DESIGNATORS, " ")
          .gsub(/\s+/, " ")
          .strip
      end

      def area_name_matches_query?(normalized_name, normalized_query)
        tokens = normalized_query.split
        return false if tokens.length == 1 && AREA_GENERIC_QUERY_TOKENS.include?(tokens.first)

        name_matches_query?(normalized_name, normalized_query)
      end

      def area_category_match?(area, normalized_query)
        AREA_CATEGORY_ALIASES.fetch(normalized_query, []).include?(area.area_type.to_s)
      end

      def score_area_name(normalized_name, area, normalized_query)
        score = AREA_RESULT_BOOST + AREA_TYPE_BOOSTS.fetch(area.area_type.to_s, 80)
        score += 1900 if normalized_name == normalized_query
        score += 1800 if normalized_query.include?(normalized_name)
        score += 1100 if normalized_name.start_with?(normalized_query)
        score += 720 if normalized_name.include?(normalized_query)
        score += 340 if normalized_query.split.all? { |token| normalized_name.include?(token) }
        score
      end

      def result_type_order(suggestion)
        (suggestion[:result_type].to_s == "area") ? 0 : 1
      end

      def score_name(name_row, place, normalized_query)
        score = place.search_rank.to_i + name_row.weight.to_i + TYPE_BOOSTS.fetch(place.place_type.to_s, 20)
        normalized_name = name_row.normalized_name.to_s

        score += 1000 if normalized_name == normalized_query
        score += 1000 if normalized_query.include?(normalized_name)
        score += 650 if normalized_name.start_with?(normalized_query)
        score += 420 if normalized_name.include?(normalized_query)
        score += 180 if normalized_query.split.all? { |token| normalized_name.include?(token) }
        score
      end

      def type_query_score(place, category_types)
        category_types.include?(place.place_type.to_s) ? 760 : 0
      end

      def category_place_types(normalized_query)
        CATEGORY_TYPE_ALIASES.fetch(normalized_query, [])
      end

      def match_type_for(place, normalized_name, normalized_query, category_types)
        return match_type(normalized_name, normalized_query) if name_matches_query?(normalized_name, normalized_query)
        return "place_type" if category_types.include?(place.place_type.to_s)

        match_type(normalized_name, normalized_query)
      end

      def match_type(normalized_name, normalized_query)
        return "exact" if normalized_name == normalized_query
        return "prefix" if normalized_name.start_with?(normalized_query)
        return "contains" if normalized_name.include?(normalized_query)
        return "name_with_context" if normalized_query.include?(normalized_name)

        "token"
      end

      def name_matches_query?(normalized_name, normalized_query)
        normalized_name == normalized_query ||
          normalized_name.start_with?(normalized_query) ||
          normalized_name.include?(normalized_query) ||
          normalized_query.include?(normalized_name) ||
          normalized_query.split.all? { |token| normalized_name.include?(token) }
      end

      # Quiet by design: what it is, where it is, which state — one middot line.
      def subtitle_for(place, areas)
        metadata = place_metadata(place)
        where = areas.first&.fetch(:name) || metadata["forest_name"] || county_label(metadata["county_name"])
        [labelize(place.place_type), where, States.name_for(place.state_code)].compact.join(" · ")
      end

      def area_subtitle_for(area)
        states = area.state_codes.to_s.split(",").filter_map { |code| States.name_for(code.strip) }.join(", ")
        [labelize(area.area_type), states.empty? ? nil : states].compact.join(" · ")
      end

      def context_score(areas)
        areas.any? ? 140 : 0
      end

      def context_query_score(normalized_query, normalized_name, place, areas)
        extra_tokens = normalized_query.split - normalized_name.to_s.split
        return 0 if extra_tokens.empty?

        # Whole tokens, not substrings — "hood" must match Hood River, never
        # hide inside a Hoodoo quad name.
        context_tokens = Normalizer.normalize(context_values_for(place, areas).join(" ")).split
        matching_tokens = extra_tokens.count { |token| context_tokens.include?(token) }
        score = matching_tokens * 120
        score += 280 if matching_tokens == extra_tokens.length
        score -= 220 if matching_tokens.zero?
        score
      end

      def context_values_for(place, areas)
        metadata = place_metadata(place)
        [
          place.state_code,
          States.name_for(place.state_code),
          metadata["county_name"],
          metadata["map_name"],
          metadata["state_name"],
          metadata["source_feature_class"],
          metadata["forest_name"],
          metadata["source_activity"],
          metadata["activity_group"],
          *areas.flat_map { |area| [area[:slug], area[:name]] }
        ].compact
      end

      def place_metadata(place)
        place.respond_to?(:metadata) ? place.metadata : {}
      end

      def county_label(value)
        return if value.to_s.empty?

        value.to_s.end_with?(" County") ? value.to_s : "#{value} County"
      end

      def labelize(value)
        value.to_s.tr("_", " ").split.map(&:capitalize).join(" ")
      end
    end
  end
end
