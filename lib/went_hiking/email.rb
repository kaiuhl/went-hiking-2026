# frozen_string_literal: true

require "aws-sdk-sesv2"
require "went_hiking/email_renderer"

module WentHiking
  module Email
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

      client.send_email(
        from_email_address: ENV.fetch("SES_FROM_EMAIL"),
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
