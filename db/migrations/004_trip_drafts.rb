# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:trips) do
      add_column :status, String, null: false, default: "published"
      add_column :published_at, DateTime
      add_index :status
    end

    from(:trips).update(published_at: Sequel[:created_at])
  end

  down do
    alter_table(:trips) do
      drop_index :status
      drop_column :published_at
      drop_column :status
    end
  end
end
