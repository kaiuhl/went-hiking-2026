ENV["APP_ENV"] ||= ENV.fetch("RACK_ENV", "development")
ENV["RACK_ENV"] ||= ENV["APP_ENV"]

require "bundler/setup"
require "json"
require "logger"
require "pathname"

require "dotenv/load" unless ENV["APP_ENV"] == "production"

require "que"
require "sequel"

module WentHiking
  class ConfigurationError < StandardError; end

  # Settings production cannot start without. SES_FROM_EMAIL is here because
  # its absence is silent by design everywhere else: delivery falls back to a
  # .eml in a container-local outbox, so signups and password resets would look
  # like they worked and simply never arrive. Better to refuse to boot.
  REQUIRED_PRODUCTION_ENV = {
    "SES_FROM_EMAIL" => "the From address for account email (verification, password resets, hike follows)"
  }.freeze

  def self.root
    @root ||= File.expand_path("..", __dir__)
  end

  def self.env
    ENV.fetch("APP_ENV", "development")
  end

  def self.production?
    env == "production"
  end

  def self.test?
    env == "test"
  end

  def self.database_url
    if test?
      ENV.fetch("TEST_DATABASE_URL", "sqlite::memory:")
    else
      ENV.fetch("DATABASE_URL", "postgres://wenthiking:wenthiking@localhost:5432/wenthiking_development")
    end
  end

  def self.db
    @db ||= Sequel.connect(database_url, max_connections: Integer(ENV.fetch("DB_POOL", "5"))).tap do |database|
      database.loggers << Logger.new($stdout) if ENV["SQL_LOG"] == "1"
      Que.connection = database if database.database_type == :postgres
    end
  end

  def self.public_base_url
    ENV.fetch("PUBLIC_BASE_URL", production? ? "https://wenthiking.com" : "http://localhost:9292")
  end

  def self.media_base_url
    media_base_url_configured? ? ENV.fetch("MEDIA_BASE_URL") : public_base_url
  end

  # True when a dedicated media host (CDN/S3) is configured. When it is not, the
  # app serves /system/* itself from local storage instead of redirecting to
  # public_base_url, which would be an infinite loop.
  def self.media_base_url_configured?
    !ENV["MEDIA_BASE_URL"].to_s.strip.empty?
  end

  def self.validate_production_env!(env = ENV)
    return unless production?

    missing = REQUIRED_PRODUCTION_ENV.reject { |key, _| env[key].to_s.strip != "" }
    return if missing.empty?

    details = missing.map { |key, purpose| "  #{key} — #{purpose}" }.join("\n")
    raise ConfigurationError, "Went Hiking cannot start in production without:\n#{details}"
  end
end

$LOAD_PATH.unshift(File.join(WentHiking.root, "lib"))

# Every production process loads this file, so the check covers the web app,
# the worker, and rake alike.
WentHiking.validate_production_env!
