# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:accounts) do
      primary_key :id
      Integer :legacy_user_id, unique: true
      String :email, null: false, unique: true
      String :name, null: false
      String :slug, null: false
      Integer :status_id, null: false, default: 1
      String :location
      TrueClass :admin, null: false, default: false
      String :avatar_file_name
      String :avatar_content_type
      Integer :avatar_file_size
      DateTime :legacy_last_request_at
      DateTime :verified_at
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      index :slug
      index :legacy_user_id
    end

    create_table(:account_password_hashes) do
      foreign_key :id, :accounts, primary_key: true, on_delete: :cascade
      String :password_hash, null: false
    end

    create_table(:account_verification_keys) do
      foreign_key :id, :accounts, primary_key: true, on_delete: :cascade
      String :key, null: false
      DateTime :requested_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :email_last_sent, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table(:account_password_reset_keys) do
      foreign_key :id, :accounts, primary_key: true, on_delete: :cascade
      String :key, null: false
      DateTime :deadline, null: false
      DateTime :email_last_sent, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table(:account_login_failures) do
      foreign_key :id, :accounts, primary_key: true, on_delete: :cascade
      Integer :number, null: false, default: 1
    end

    create_table(:account_lockouts) do
      foreign_key :id, :accounts, primary_key: true, on_delete: :cascade
      String :key, null: false
      DateTime :deadline, null: false
      DateTime :email_last_sent, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table(:account_session_keys) do
      foreign_key :id, :accounts, primary_key: true, on_delete: :cascade
      String :key, null: false
    end

    create_table(:signup_attempts) do
      primary_key :id
      String :email
      String :ip_address
      String :user_agent
      TrueClass :honeypot_filled, null: false, default: false
      String :result, null: false
      DateTime :created_at, null: false
    end

    create_table(:trips) do
      primary_key :id
      Integer :legacy_trip_id, unique: true
      foreign_key :account_id, :accounts, null: false, on_delete: :cascade
      String :name, null: false
      String :slug, null: false
      String :source_url
      Integer :nights, null: false, default: 0
      Float :mileage
      Integer :elevation
      DateTime :hiked_at, null: false
      Float :lat
      Float :lng
      String :report_markdown, text: true
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      index :legacy_trip_id
      index [:account_id, :hiked_at]
      index :slug
    end

    create_table(:photos) do
      primary_key :id
      Integer :legacy_photo_id, unique: true
      foreign_key :account_id, :accounts, null: false, on_delete: :cascade
      foreign_key :trip_id, :trips, null: false, on_delete: :cascade
      String :legacy_image_file_name
      String :content_type
      Integer :file_size
      Integer :width
      Integer :height
      DateTime :taken_at
      Float :lat
      Float :lng
      String :caption, text: true
      String :camera_model
      String :camera_exposure
      Float :camera_f_stop
      Integer :camera_iso
      TrueClass :legacy_stats_added, null: false, default: false
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      index :legacy_photo_id
      index :trip_id
      index :account_id
      index :taken_at
    end

    create_table(:photo_variants) do
      primary_key :id
      foreign_key :photo_id, :photos, null: false, on_delete: :cascade
      String :style, null: false
      String :filename, null: false
      String :legacy_path
      String :s3_key
      Integer :file_size
      Integer :width
      Integer :height
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      index [:photo_id, :style], unique: true
      index :s3_key
    end

    create_table(:comments) do
      primary_key :id
      Integer :legacy_comment_id, unique: true
      foreign_key :account_id, :accounts, null: false, on_delete: :cascade
      foreign_key :trip_id, :trips, null: false, on_delete: :cascade
      String :body_markdown, text: true, null: false
      TrueClass :legacy_read_only, null: false, default: true
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      index :legacy_comment_id
      index :trip_id
    end

    create_table(:hearts) do
      primary_key :id
      Integer :legacy_heart_id, unique: true
      foreign_key :account_id, :accounts, null: false, on_delete: :cascade
      foreign_key :trip_id, :trips, null: false, on_delete: :cascade
      TrueClass :legacy_read_only, null: false, default: true
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      index :legacy_heart_id
      index [:account_id, :trip_id], unique: true
      index :trip_id
    end

    create_table(:import_runs) do
      primary_key :id
      String :source, null: false
      String :status, null: false
      String :summary_json, text: true
      DateTime :started_at, null: false
      DateTime :finished_at
      DateTime :created_at, null: false
      DateTime :updated_at, null: false
    end
  end
end
