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

  desc "Load development seed data"
  task seed: :migrate do
    require_relative "db/seeds"

    WentHiking::Seeds.run
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
