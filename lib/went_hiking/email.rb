# frozen_string_literal: true

require "aws-sdk-sesv2"
require "fileutils"
require "securerandom"
require "time"
require "went_hiking/email_renderer"

module WentHiking
  module Email
    DEFAULT_FROM = "Went Hiking <hello@wenthiking.com>"
    Message = Struct.new(:to, :subject, :text_body, :html_body, :cta_label, :cta_url, keyword_init: true) do
      def body
        text_body
      end
    end

    module_function

    def render(to:, subject:, body:)
      rendered = EmailRenderer.new.render(to: to, subject: subject, body: body)
      Message.new(**rendered)
    end

    def render_template(to:, subject:, headline:, intro:, cta_label: nil, cta_url: nil, outro: nil, unsubscribe_url: nil)
      rendered = EmailRenderer.new.render_template(
        to: to,
        subject: subject,
        headline: headline,
        intro: intro,
        cta_label: cta_label,
        cta_url: cta_url,
        outro: outro,
        unsubscribe_url: unsubscribe_url
      )
      Message.new(**rendered)
    end

    def deliver(message)
      if WentHiking.test? || ENV["EMAIL_DELIVERY"] == "log"
        deliveries << message
        return true
      end

      from = from_address
      if ENV["EMAIL_DELIVERY"] == "outbox"
        deliver_to_outbox(message, from, "EMAIL_DELIVERY=outbox")
        return true
      end

      if from.empty?
        deliver_to_outbox(message, DEFAULT_FROM, "SES_FROM_EMAIL is not configured")
        return true
      end

      client.send_email(
        from_email_address: from,
        destination: {to_addresses: [message.to]},
        content: {
          simple: {
            subject: {data: message.subject, charset: "UTF-8"},
            body: {
              text: {data: message.text_body, charset: "UTF-8"},
              html: {data: message.html_body, charset: "UTF-8"}
            }
          }
        }
      )
      true
    end

    def from_address
      ENV["SES_FROM_EMAIL"].to_s.strip
    end

    def outbox_dir
      ENV.fetch("EMAIL_OUTBOX_DIR", File.join(WentHiking.root, "tmp/outbox"))
    end

    # Fallback delivery for environments with no SES credentials. Writing a real
    # .eml keeps signup and password reset flows working end to end instead of
    # raising a KeyError mid-request.
    def deliver_to_outbox(message, from, reason)
      FileUtils.mkdir_p(outbox_dir)
      path = File.join(outbox_dir, outbox_filename(message))
      File.write(path, outbox_document(message, from))
      warn("[went-hiking] email written to the local outbox (#{reason}): #{path}")
      path
    end

    def outbox_filename(message)
      stamp = Time.now.utc.strftime("%Y%m%dT%H%M%S")
      "#{stamp}-#{outbox_slug(message.to)}-#{outbox_slug(message.subject)}.eml"
    end

    def outbox_slug(value)
      slug = value.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
      slug.empty? ? "message" : slug[0, 48]
    end

    def outbox_document(message, from)
      boundary = "wenthiking-#{SecureRandom.hex(12)}"

      <<~EMAIL
        From: #{header_value(from)}
        To: #{header_value(message.to)}
        Subject: #{header_value(message.subject)}
        Date: #{Time.now.rfc2822}
        MIME-Version: 1.0
        Content-Type: multipart/alternative; boundary="#{boundary}"

        --#{boundary}
        Content-Type: text/plain; charset=UTF-8

        #{message.text_body}
        --#{boundary}
        Content-Type: text/html; charset=UTF-8

        #{message.html_body}
        --#{boundary}--
      EMAIL
    end

    def header_value(value)
      value.to_s.gsub(/[\r\n]+/, " ").strip
    end

    def deliveries
      @deliveries ||= []
    end

    def clear_deliveries
      deliveries.clear
    end

    def client
      @client ||= Aws::SESV2::Client.new(region: ENV.fetch("AWS_REGION", "us-west-2"))
    end
  end
end
