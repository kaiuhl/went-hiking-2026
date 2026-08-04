# frozen_string_literal: true

# The gazetteer: datasets (with licensing, which is why license_name is NOT
# NULL), places, and their searchable names. Ported from Big Fluffy Puffy's
# places layer. The trigram index is what makes leading-wildcard name lookups
# viable; the [latitude, longitude] index serves bbox scans (nearest-place
# backfill, "hikes near"). Postgres-only, like the Que schema: an sqlite boot
# simply has no gazetteer.
Sequel.migration do
  up do
    next unless database_type == :postgres

    run "CREATE EXTENSION IF NOT EXISTS pg_trgm"

    create_table(:place_datasets) do
      primary_key :id
      String :slug, null: false, unique: true
      String :name, null: false
      String :source_url
      String :license_name, null: false
      String :license_url
      String :attribution_text, text: true
      DateTime :retrieved_at
      column :metadata_json, :jsonb, null: false, default: Sequel.lit("'{}'::jsonb")
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table(:places) do
      primary_key :id
      String :slug, null: false, unique: true
      String :name, null: false
      String :place_type, null: false
      Float :latitude
      Float :longitude
      column :geometry_json, :jsonb
      String :state_code
      foreign_key :source_dataset_id, :place_datasets, on_delete: :set_null
      String :source_external_id
      String :source_url
      Float :confidence, null: false, default: 0.0
      Integer :search_rank, null: false, default: 0
      TrueClass :active, null: false, default: true
      column :metadata_json, :jsonb, null: false, default: Sequel.lit("'{}'::jsonb")
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :active
      index :place_type
      index :state_code
      index :source_external_id
      index :source_dataset_id
      index [:active, :search_rank]
      index [:latitude, :longitude]
    end

    create_table(:place_names) do
      primary_key :id
      foreign_key :place_id, :places, null: false, on_delete: :cascade
      String :name, null: false
      String :normalized_name, null: false
      String :kind, null: false, default: "official"
      Integer :weight, null: false, default: 0
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index [:place_id, :normalized_name], unique: true, name: :place_names_place_normalized_uidx
      index [:kind, :weight]
    end

    run "CREATE INDEX place_names_normalized_trgm_idx ON place_names USING gin (normalized_name gin_trgm_ops)"
  end

  down do
    next unless database_type == :postgres

    run "DROP INDEX IF EXISTS place_names_normalized_trgm_idx"
    drop_table(:place_names)
    drop_table(:places)
    drop_table(:place_datasets)
  end
end
