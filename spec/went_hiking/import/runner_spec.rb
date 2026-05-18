require_relative "../../spec_helper"
require "went_hiking/import/runner"

RSpec.describe WentHiking::Import::Runner do
  it "includes skipped orphan rows and avatar-only users in the import summary" do
    source = Sequel.sqlite
    source.create_table(:users) do
      primary_key :id
      String :email
      String :name
      String :avatar_file_name
      DateTime :created_at
      DateTime :updated_at
    end
    source.create_table(:trips) do
      primary_key :id
      Integer :user_id
      String :name
      DateTime :hiked_at
      DateTime :created_at
      DateTime :updated_at
    end
    source.create_table(:photos) do
      primary_key :id
      Integer :user_id
      Integer :trip_id
      String :image_file_name
      DateTime :created_at
      DateTime :updated_at
    end

    now = Time.now
    source[:users].insert(id: 1, email: "hiker@example.com", name: "Hiker", avatar_file_name: "avatar.jpg", created_at: now, updated_at: now)
    source[:users].insert(id: 2, email: "avatar@example.com", name: "Avatar Only", avatar_file_name: "avatar.jpg", created_at: now, updated_at: now)
    source[:trips].insert(id: 10, user_id: 1, name: "Durable Trip", hiked_at: now, created_at: now, updated_at: now)
    source[:photos].insert(id: 20, user_id: 1, trip_id: 999, image_file_name: "orphan.jpg", created_at: now, updated_at: now)

    summary = described_class.new(source_db: source).run

    expect(summary[:accounts]).to eq(1)
    expect(summary[:trips]).to eq(1)
    expect(summary[:skipped_photos]).to eq(1)
    expect(summary[:orphan_references]).to include(missing_trip: 1)
    expect(summary[:skipped_rows]).to include(
      table: :photos,
      legacy_id: 20,
      reason: :missing_trip,
      references: {legacy_user_id: 1, legacy_trip_id: 999}
    )
    expect(summary[:avatar_only_user_count]).to eq(1)
    expect(summary[:avatar_only_user_ids_sample]).to eq([2])
  end
end
