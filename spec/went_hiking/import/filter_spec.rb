require_relative "../../spec_helper"
require "went_hiking/import/filter"

RSpec.describe WentHiking::Import::Filter do
  it "keeps users with durable content" do
    source = Sequel.sqlite
    source.create_table(:trips) { Integer :user_id }
    source.create_table(:comments) { Integer :user_id }
    source.create_table(:hearts) { Integer :user_id }
    source[:trips].insert(user_id: 10)
    source[:comments].insert(user_id: 11)
    source[:hearts].insert(user_id: 10)

    expect(described_class.new(source).durable_user_ids).to eq([10, 11])
  end
end
