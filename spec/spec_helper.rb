ENV["APP_ENV"] = "test"
ENV["RACK_ENV"] = "test"
ENV["TEST_DATABASE_URL"] ||= "sqlite::memory:"
ENV["SESSION_SECRET"] ||= "test-session-secret-test-session-secret-test-session-secret-test-session-secret"
ENV["MEDIA_BASE_URL"] ||= "https://media.example.test"
ENV["UPLOAD_STORAGE"] ||= "local"
ENV["LOCAL_UPLOAD_ROOT"] ||= File.expand_path("../tmp/test-uploads", __dir__)

require "fileutils"
require "rack/test"
require "rspec"

require_relative "../config/boot"
require "sequel/extensions/migration"

module TestDatabase
  module_function

  def migrate!
    Sequel::Migrator.run(WentHiking.db, File.join(WentHiking.root, "db/migrations"))
  end

  def reset!
    WentHiking.db.run("PRAGMA foreign_keys = OFF") if WentHiking.db.database_type == :sqlite
    (WentHiking.db.tables - [:schema_info]).each do |table|
      WentHiking.db[table].delete
    end
    WentHiking.db.run("PRAGMA foreign_keys = ON") if WentHiking.db.database_type == :sqlite
  end
end

TestDatabase.migrate!

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end

  config.before do
    TestDatabase.reset!
    FileUtils.rm_rf(ENV.fetch("LOCAL_UPLOAD_ROOT"))
  end
end
