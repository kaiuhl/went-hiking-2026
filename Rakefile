default_tasks = []

begin
  require "rspec/core/rake_task"

  RSpec::Core::RakeTask.new(:spec)
  default_tasks << :spec
rescue LoadError
  warn "RSpec is not available in this bundle; skipping spec rake task."
end

namespace :spec do
  # The compose editor promises to hand the server back exactly the markdown it
  # was given, and the only thing standing behind that promise is this harness.
  # It is plain node with no dependencies so it can ride along with the Ruby
  # suite, but the deploy image carries no node at all, so a missing runtime is
  # a warning rather than a failure.
  desc "Run the compose editor markdown round-trip harness"
  task :js do
    script = File.join(__dir__, "spec/js/editor_round_trip.js")
    node = ENV.fetch("NODE", "node")

    unless system(node, "--version", out: File::NULL, err: File::NULL)
      warn "#{node} is not available; skipping spec/js/editor_round_trip.js."
      next
    end

    abort "Editor round-trip harness failed." unless system(node, script)
  end
end

default_tasks << "spec:js"
task default: default_tasks

namespace :db do
  desc "Run Sequel migrations"
  task :migrate do
    require_relative "config/boot"
    require "sequel/extensions/migration"

    Sequel::Migrator.run(WentHiking.db, File.join(WentHiking.root, "db/migrations"))
  end

  desc "Load development seed data"
  task seed: :migrate do
    require_relative "db/seeds"

    WentHiking::Seeds.run
  end

  desc "Fill in missing photo and variant pixel dimensions from stored files"
  task :backfill_photo_dimensions do
    require_relative "config/boot"
    require "went_hiking/photo_dimension_backfill"

    result = WentHiking::PhotoDimensionBackfill.call(logger: ->(line) { puts line })
    puts "Backfilled #{result}"
  end
end

namespace :places do
  desc "Import configured place datasets into Postgres"
  task :import do
    require_relative "config/boot"
    require "went_hiking/places/importer"

    counts = WentHiking::Places::Importer.new.import
    puts "Imported #{counts[:places]} places and #{counts[:names]} names from #{counts[:datasets]} place datasets."
  end

  desc "Import one configured place dataset by slug"
  task :import_dataset, [:dataset_slug] do |_task, args|
    require_relative "config/boot"
    require "went_hiking/places/importer"

    slug = args[:dataset_slug].to_s
    raise "Usage: rake places:import_dataset[dataset_slug]" if slug.empty?

    counts = WentHiking::Places::Importer.new.import(dataset_slugs: [slug])
    puts "Imported #{counts[:places]} places and #{counts[:names]} names from #{counts[:datasets]} place datasets."
  end

  desc "Seed curated destinations from config/place_manual.yml"
  task :seed_manual do
    require_relative "config/boot"
    require "went_hiking/places/manual_seeder"

    counts = WentHiking::Places::ManualSeeder.new.seed
    puts "Seeded #{counts[:places]} curated places and #{counts[:names]} names."
  end

  desc "Fetch containing-area boundaries (forests, wilderness, parks) into the areas table"
  task :refresh_areas do
    require_relative "config/boot"
    require "went_hiking/places/area_refresher"

    counts = WentHiking::Places::AreaRefresher.new.refresh
    puts "Refreshed #{counts[:areas]} area boundaries."
  end

  desc "Resolve place-in-area containment matches (optionally for one dataset)"
  task :resolve, [:dataset_slug] do |_task, args|
    require_relative "config/boot"
    require "went_hiking/places/resolver"

    counts = WentHiking::Places::Resolver.new.resolve(dataset_slug: args[:dataset_slug])
    puts "Resolved #{counts[:area_matches]} place-area matches."
  end

  desc "Import, seed, refresh areas, and resolve — the whole gazetteer"
  task :refresh do
    Rake::Task["places:import"].invoke
    Rake::Task["places:seed_manual"].invoke
    Rake::Task["places:refresh_areas"].invoke
    Rake::Task["places:resolve"].invoke
  end
end

namespace :trips do
  desc "Name existing trips from their coordinates (DRY_RUN=1 to preview, FORCE=1 to redo auto rows)"
  task :backfill_locations do
    require_relative "config/boot"
    require "went_hiking/places"

    counts = WentHiking::Places::TripLocator.new.backfill(
      dry_run: ENV["DRY_RUN"] == "1",
      force: ENV["FORCE"] == "1",
      logger: ->(line) { puts line }
    )
    verb = (ENV["DRY_RUN"] == "1") ? "Would name" : "Named"
    puts "#{verb} #{counts[:named]} of #{counts[:trips]} trips (#{counts[:areas]} with areas)."
  end
end

namespace :email do
  desc "Write sample auth email previews to tmp/email-previews"
  task :preview do
    require_relative "config/boot"
    require "fileutils"
    require "went_hiking/email"

    preview_dir = File.join(WentHiking.root, "tmp/email-previews")
    FileUtils.mkdir_p(preview_dir)

    samples = {
      "verify-account" => ["Verify Account", "Someone has created an account with this email address. If you created this account, please go to #{WentHiking.public_base_url}/verify-account?key=preview-token to verify the account."],
      "reset-password" => ["Reset Password", "Someone has requested a password reset for the account with this email address. If you requested a password reset, please go to #{WentHiking.public_base_url}/reset-password?key=preview-token to reset the password for the account."],
      "unlock-account" => ["Unlock Account", "Someone has requested that the account with this email be unlocked. If you requested the unlocking of this account, please go to #{WentHiking.public_base_url}/unlock-account?key=preview-token to unlock this account."]
    }

    samples.each do |name, (subject, body)|
      message = WentHiking::Email.render(to: "hiker@example.com", subject: subject, body: body)
      File.write(File.join(preview_dir, "#{name}.html"), message.html_body)
      File.write(File.join(preview_dir, "#{name}.txt"), message.text_body)
    end

    puts "Wrote #{samples.size} email previews to #{preview_dir}"
  end
end
