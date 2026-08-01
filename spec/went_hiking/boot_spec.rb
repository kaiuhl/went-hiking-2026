require_relative "../spec_helper"
require "went_hiking/email"

RSpec.describe "production configuration" do
  describe ".validate_production_env!" do
    it "refuses to boot production without SES_FROM_EMAIL" do
      allow(WentHiking).to receive(:production?).and_return(true)

      expect { WentHiking.validate_production_env!({}) }
        .to raise_error(WentHiking::ConfigurationError, /SES_FROM_EMAIL/)
    end

    it "names what the missing setting is for" do
      allow(WentHiking).to receive(:production?).and_return(true)

      expect { WentHiking.validate_production_env!({"SES_FROM_EMAIL" => "   "}) }
        .to raise_error(WentHiking::ConfigurationError, /verification, password resets/)
    end

    # Every one of these falls back to a constant committed to this repository:
    # session cookies, password reset tokens and upload tickets are all signed
    # with it, so a production process running on the fallback is one anyone
    # reading the source can forge against.
    it "refuses to boot production without SESSION_SECRET" do
      allow(WentHiking).to receive(:production?).and_return(true)

      expect { WentHiking.validate_production_env!({"SES_FROM_EMAIL" => "hello@wenthiking.com"}) }
        .to raise_error(WentHiking::ConfigurationError, /SESSION_SECRET/)
    end

    it "boots production when everything required is set" do
      allow(WentHiking).to receive(:production?).and_return(true)

      expect {
        WentHiking.validate_production_env!(
          "SES_FROM_EMAIL" => "Went Hiking <hello@wenthiking.com>",
          "SESSION_SECRET" => "a-real-secret-from-the-deploy-environment"
        )
      }.not_to raise_error
    end

    it "leaves development and test alone" do
      expect { WentHiking.validate_production_env!({}) }.not_to raise_error
    end
  end

  # The outbox fallback is a development convenience. In production it would
  # turn an undelivered password reset into a file nobody ever reads.
  describe "email delivery without a From address" do
    before do
      allow(WentHiking).to receive(:test?).and_return(false)
      allow(WentHiking::Email).to receive(:from_address).and_return("")
    end

    it "raises in production rather than writing to the outbox" do
      allow(WentHiking).to receive(:production?).and_return(true)
      message = WentHiking::Email.render(to: "hiker@example.com", subject: "Verify Account", body: "Please verify.")

      expect(WentHiking::Email).not_to receive(:deliver_to_outbox)
      expect { WentHiking::Email.deliver(message) }
        .to raise_error(WentHiking::ConfigurationError, /SES_FROM_EMAIL/)
    end

    it "still writes to the outbox outside production" do
      outbox = File.join(WentHiking.root, "tmp/spec-boot-outbox")
      FileUtils.rm_rf(outbox)
      allow(WentHiking::Email).to receive(:outbox_dir).and_return(outbox)
      message = WentHiking::Email.render(to: "hiker@example.com", subject: "Verify Account", body: "Please verify.")

      expect { WentHiking::Email.deliver(message) }.not_to raise_error
      expect(Dir[File.join(outbox, "*.eml")].size).to eq(1)
    end
  end
end
