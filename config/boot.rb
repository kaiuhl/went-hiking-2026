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
    ENV.fetch("MEDIA_BASE_URL", public_base_url)
  end
end

$LOAD_PATH.unshift(File.join(WentHiking.root, "lib"))
