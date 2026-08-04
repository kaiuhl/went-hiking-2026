# frozen_string_literal: true

# Named containing areas — national forests, national parks, wilderness — with
# their boundaries stored as GeoJSON in the row rather than a checked-in file:
# a national set is tens of megabytes, and upserting by slug keeps trip and
# place foreign keys alive across refreshes. place_area_matches is the
# precomputed point-in-polygon answer, so runtime search never touches
# geometry. Allowed area_type values live in WentHiking::Places::Area.
Sequel.migration do
  up do
    next unless database_type == :postgres

    create_table(:areas) do
      primary_key :id
      String :slug, null: false, unique: true
      String :name, null: false
      String :area_type, null: false
      String :agency
      String :region_code
      String :state_codes
      String :official_url
      String :boundary_source_url
      column :boundary_json, :jsonb
      DateTime :boundary_updated_at
      TrueClass :active, null: false, default: true
      column :metadata_json, :jsonb, null: false, default: Sequel.lit("'{}'::jsonb")
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :active
      index :area_type
    end

    create_table(:place_area_matches) do
      primary_key :id
      foreign_key :place_id, :places, null: false, on_delete: :cascade
      foreign_key :area_id, :areas, null: false, on_delete: :cascade
      String :relationship, null: false
      String :match_method, null: false
      Float :confidence, null: false, default: 0.0
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index [:place_id, :area_id], unique: true, name: :place_area_matches_place_area_uidx
      index [:area_id, :relationship]
    end
  end

  down do
    next unless database_type == :postgres

    drop_table(:place_area_matches)
    drop_table(:areas)
  end
end
