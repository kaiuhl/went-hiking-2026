begin
  require "rspec/core/rake_task"

  RSpec::Core::RakeTask.new(:spec)
  task default: :spec
rescue LoadError
  warn "RSpec is not available in this bundle; skipping spec rake task."
end

namespace :db do
  desc "Run Sequel migrations"
  task :migrate do
    require_relative "config/boot"
    require "sequel/extensions/migration"

    Sequel::Migrator.run(WentHiking.db, File.join(WentHiking.root, "db/migrations"))
  end
end
