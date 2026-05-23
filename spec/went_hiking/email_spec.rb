require_relative "../spec_helper"
require "went_hiking/email"

RSpec.describe WentHiking::Email do
  let(:verify_url) { "https://wenthiking.com/verify-account?key=preview-token" }
  let(:verify_body) { "Someone has created an account with this email address. If you created this account, please go to #{verify_url} to verify the account." }

  before do
    described_class.clear_deliveries
  end

  describe ".render" do
    it "renders branded multipart verification email" do
      message = described_class.render(to: "hiker@example.com", subject: "Verify Account", body: verify_body)

      expect(message.to).to eq("hiker@example.com")
      expect(message.subject).to eq("Verify your Went Hiking account")
      expect(message.text_body).to include("Ready to join the trail log?")
      expect(message.text_body).to include(verify_url)
      expect(message.html_body).to include("/images/email-wordmark.png")
      expect(message.html_body).to include("Verify account")
      expect(message.html_body).to include(verify_url)
      expect(message.html_body).to include("style=")
      expect(message.html_body).not_to include("<style")
    end

    it "renders reset and unlock email copy" do
      reset = described_class.render(to: "hiker@example.com", subject: "Reset Password", body: "Go to https://wenthiking.com/reset-password?key=abc")
      unlock = described_class.render(to: "hiker@example.com", subject: "Unlock Account", body: "Go to https://wenthiking.com/unlock-account?key=abc")

      expect(reset.subject).to eq("Reset your Went Hiking password")
      expect(reset.html_body).to include("Reset password")
      expect(unlock.subject).to eq("Unlock your Went Hiking account")
      expect(unlock.html_body).to include("Unlock account")
    end

    it "falls back for future Rodauth emails" do
      message = described_class.render(to: "hiker@example.com", subject: "Security Notice", body: "Read this: https://wenthiking.com/account")

      expect(message.subject).to eq("Security Notice")
      expect(message.text_body).to include("Read this")
      expect(message.html_body).to include("Open link")
      expect(message.html_body).to include("https://wenthiking.com/account")
    end
  end

  describe ".deliver" do
    it "stores multipart messages in log mode" do
      message = described_class.render(to: "hiker@example.com", subject: "Verify Account", body: verify_body)

      described_class.deliver(message)

      expect(described_class.deliveries.first.text_body).to include(verify_url)
      expect(described_class.deliveries.first.html_body).to include("Verify account")
    end

    it "sends text and html bodies to SES outside log mode" do
      message = described_class.render(to: "hiker@example.com", subject: "Verify Account", body: verify_body)
      previous_delivery_mode = ENV.delete("EMAIL_DELIVERY")
      client = instance_double(Aws::SESV2::Client)

      allow(WentHiking).to receive(:test?).and_return(false)
      allow(described_class).to receive(:client).and_return(client)
      expect(client).to receive(:send_email) do |payload|
        expect(payload[:from_email_address]).to eq(ENV.fetch("SES_FROM_EMAIL"))
        expect(payload[:destination]).to eq(to_addresses: ["hiker@example.com"])
        expect(payload.dig(:content, :simple, :subject, :data)).to eq("Verify your Went Hiking account")
        expect(payload.dig(:content, :simple, :body, :text, :data)).to include(verify_url)
        expect(payload.dig(:content, :simple, :body, :html, :data)).to include("Verify account")
      end

      described_class.deliver(message)
    ensure
      ENV["EMAIL_DELIVERY"] = previous_delivery_mode if previous_delivery_mode
    end
  end
end
