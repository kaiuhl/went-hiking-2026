# frozen_string_literal: true

require "sequel/extensions/pg_json"
require_relative "../models"

module WentHiking
  module Places
    WentHiking.db.extension :pg_json

    module Jsonb
      def self.wrap(value)
        return if value.nil?
        return value if value.is_a?(Sequel::Postgres::JSONBObject)

        Sequel.pg_jsonb(value)
      end
    end

    class PlaceDataset < Sequel::Model(:place_datasets)
      one_to_many :places, key: :source_dataset_id

      def metadata
        metadata_json&.to_hash || metadata_json || {}
      end
    end

    class Place < Sequel::Model(:places)
      many_to_one :source_dataset, class: "WentHiking::Places::PlaceDataset", key: :source_dataset_id
      one_to_many :place_names
      one_to_many :place_area_matches

      dataset_module do
        def active
          where(active: true)
        end
      end

      def geometry
        geometry_json&.to_hash || geometry_json
      end

      def metadata
        metadata_json&.to_hash || metadata_json || {}
      end
    end

    class PlaceName < Sequel::Model(:place_names)
      many_to_one :place
    end

    class Area < Sequel::Model(:areas)
      one_to_many :place_area_matches

      # Most specific first: a hike inside Goat Rocks is "Goat Rocks
      # Wilderness", not the national forest the wilderness sits in.
      TYPES_BY_SPECIFICITY = %w[wilderness national_park national_forest].freeze

      dataset_module do
        def active
          where(active: true)
        end
      end

      def specificity
        TYPES_BY_SPECIFICITY.index(area_type) || TYPES_BY_SPECIFICITY.length
      end

      def boundary
        boundary_json&.to_hash || boundary_json
      end

      def metadata
        metadata_json&.to_hash || metadata_json || {}
      end
    end

    class PlaceAreaMatch < Sequel::Model(:place_area_matches)
      many_to_one :place
      many_to_one :area
    end
  end
end
