# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:hike_follow_subscriptions) do
      primary_key :id
      foreign_key :followed_account_id, :accounts, null: false, on_delete: :cascade
      String :email, null: false
      String :status, null: false, default: "pending"
      String :confirmation_token_digest
      DateTime :confirmation_sent_at
      DateTime :confirmed_at
      DateTime :unsubscribed_at
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      index [:followed_account_id, :email], unique: true
      index :confirmation_token_digest, unique: true
      index [:followed_account_id, :status]
    end

    create_table(:hike_follow_notifications) do
      primary_key :id
      foreign_key :trip_id, :trips, null: false, on_delete: :cascade
      foreign_key :account_id, :accounts, null: false, on_delete: :cascade
      DateTime :scheduled_at, null: false
      DateTime :sent_at
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      index :trip_id, unique: true
      index :scheduled_at
    end

    create_table(:hike_follow_notification_deliveries) do
      primary_key :id
      foreign_key :notification_id, :hike_follow_notifications, null: false, on_delete: :cascade
      foreign_key :subscription_id, :hike_follow_subscriptions, null: false, on_delete: :cascade
      String :email, null: false
      String :status, null: false, default: "pending"
      String :last_error, text: true
      DateTime :sent_at
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      index [:notification_id, :subscription_id], unique: true
      index [:notification_id, :status]
    end
  end
end
