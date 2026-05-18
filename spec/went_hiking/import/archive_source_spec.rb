require_relative "../../spec_helper"
require "went_hiking/import/archive_source"

RSpec.describe WentHiking::Import::ArchiveSource do
  it "provides the dataset interface used by the legacy importer" do
    archive_path = File.join(WentHiking.root, "tmp/archive-source-spec")
    FileUtils.mkdir_p(archive_path)
    File.write(
      File.join(archive_path, "users.jsonl"),
      [
        {id: 1, name: "Durable", avatar_file_name: "face.jpg", created_at: "2025-01-02T03:04:05Z"}.to_json,
        {id: 2, name: "No Avatar", avatar_file_name: "", created_at: "2025-01-03T03:04:05Z"}.to_json
      ].join("\n")
    )

    source = described_class.new(archive_path)

    expect(source.table_exists?(:users)).to be(true)
    expect(source.table_exists?(:trips)).to be(false)
    expect(source.schema(:users).map(&:first)).to include(:id, :avatar_file_name, :created_at)
    expect(source[:users].where(id: [1]).select_map(:name)).to eq(["Durable"])
    expect(source[:users].exclude(avatar_file_name: nil).exclude(avatar_file_name: "").select_map(:id)).to eq([1])
    expect(source[:users].where(id: 1).first[:created_at]).to be_a(Time)
  end
end
