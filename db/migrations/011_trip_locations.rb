# frozen_string_literal: true

# Where a hike happened, in words. location_name/area_name are snapshots taken
# when the place is resolved, so a byline survives gazetteer rebuilds and
# deactivations; place_id/area_id keep the structured link while it lives.
# location_source separates what an author chose ("author") from what a
# backfill inferred ("auto_v1", …) — re-runs may only ever touch the latter.
# The [lat, lng] composite serves "hikes near a place" bbox queries.
#
# The columns exist on sqlite too (an sqlite boot still renders bylines); only
# the foreign keys are Postgres, since the places tables don't exist elsewhere.
Sequel.migration do
  up do
    postgres = database_type == :postgres
    alter_table(:trips) do
      if postgres
        add_foreign_key :place_id, :places, on_delete: :set_null
        add_foreign_key :area_id, :areas, on_delete: :set_null
      else
        add_column :place_id, Integer
        add_column :area_id, Integer
      end
      add_column :location_name, String
      add_column :area_name, String
      add_column :location_source, String
      add_column :location_resolved_at, DateTime

      add_index :place_id
      add_index :area_id
      add_index [:lat, :lng]
    end
  end

  down do
    alter_table(:trips) do
      drop_index [:lat, :lng]
      drop_index :area_id
      drop_index :place_id

      drop_column :location_resolved_at
      drop_column :location_source
      drop_column :area_name
      drop_column :location_name
      drop_column :area_id
      drop_column :place_id
    end
  end
end
