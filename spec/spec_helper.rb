ENV["APP_ENV"] = "test"
ENV["RACK_ENV"] = "test"
# Assigned rather than defaulted: specs assert on absolute URLs, so the base has
# to be the suite's own no matter what the surrounding container was started
# with. A dev stack on a different port must not change what a spec expects.
ENV["PUBLIC_BASE_URL"] = "http://localhost:9292"
ENV["TEST_DATABASE_URL"] ||= "sqlite::memory:"
ENV["SESSION_SECRET"] ||= "test-session-secret-test-session-secret-test-session-secret-test-session-secret"
ENV["MEDIA_BASE_URL"] ||= "https://media.example.test"
ENV["SES_FROM_EMAIL"] ||= "Went Hiking <hello@example.test>"
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

# CSRF protection is on for every non-GET route, so specs need a token. Include
# this *after* Rack::Test::Methods so the override wins, and use
# `post_without_csrf` to exercise the rejection path.
module CsrfHelpers
  CSRF_META_PATTERN = /<meta name="csrf-token" content="([^"]+)">/

  def csrf_token
    get "/about"
    last_response.body[CSRF_META_PATTERN, 1]
  end

  def post(uri, params = {}, env = {}, &block)
    skip_csrf = env.delete(:skip_csrf)
    if !skip_csrf && params.is_a?(Hash) && !params.key?("_csrf")
      params = params.merge("_csrf" => csrf_token)
    end

    super
  end

  def post_without_csrf(uri, params = {}, env = {}, &block)
    post(uri, params, env.merge(skip_csrf: true), &block)
  end
end

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
