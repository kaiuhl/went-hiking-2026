ENV["APP_ENV"] = "test"
ENV["RACK_ENV"] = "test"
# Assigned rather than defaulted: specs assert on absolute URLs, so the base has
# to be the suite's own no matter what the surrounding container was started
# with. A dev stack on a different port must not change what a spec expects.
ENV["PUBLIC_BASE_URL"] = "http://localhost:9292"
# Port 55432 is the compose postgres published to the host (compose.override.yaml);
# 5432 stays free for whatever other project owns it. In-container runs and CI
# override this with their own TEST_DATABASE_URL.
ENV["TEST_DATABASE_URL"] ||= "postgres://wenthiking:wenthiking@localhost:55432/wenthiking_test"
ENV["SESSION_SECRET"] ||= "test-session-secret-test-session-secret-test-session-secret-test-session-secret"
ENV["MEDIA_BASE_URL"] ||= "https://media.example.test"
ENV["SES_FROM_EMAIL"] ||= "Went Hiking <hello@example.test>"
ENV["UPLOAD_STORAGE"] ||= "local"
ENV["LOCAL_UPLOAD_ROOT"] ||= File.expand_path("../tmp/test-uploads", __dir__)

require "fileutils"
require "rack/test"
require "rspec"
require "uri"

require_relative "../config/boot"
require "sequel/extensions/migration"

module TestDatabase
  module_function

  # Creates the test database on first run so a fresh checkout needs no manual
  # createdb. The maintenance connection is short-lived, and the duplicate-
  # database rescue covers two suites racing to create it.
  def ensure_database!
    url = URI(ENV.fetch("TEST_DATABASE_URL"))
    Sequel.connect(url.to_s) { |db| db.test_connection }
  rescue Sequel::DatabaseConnectionError => error
    raise unless error.message.include?("does not exist")

    maintenance = url.dup
    maintenance.path = "/postgres"
    begin
      Sequel.connect(maintenance.to_s) do |db|
        db.run("CREATE DATABASE #{db.literal(url.path.delete_prefix("/").to_sym)}")
      end
    rescue Sequel::DatabaseError => create_error
      raise unless create_error.message.include?("already exists")
    end
  end

  def migrate!
    Sequel::Migrator.run(WentHiking.db, File.join(WentHiking.root, "db/migrations"))
  end

  # One statement over every app table: CASCADE satisfies the foreign keys, and
  # RESTART IDENTITY keeps ids starting from 1 each example — a guarantee the
  # in-memory sqlite suite used to provide for free and specs may lean on.
  def reset!
    WentHiking.db.run(truncate_sql)
  end

  def truncate_sql
    @truncate_sql ||= begin
      tables = (WentHiking.db.tables - [:schema_info]).map { |table| WentHiking.db.literal(table) }
      "TRUNCATE #{tables.join(", ")} RESTART IDENTITY CASCADE"
    end
  end
end

TestDatabase.ensure_database!
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
