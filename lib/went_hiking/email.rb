# frozen_string_literal: true

require "aws-sdk-sesv2"

module WentHiking
  module Email
    Message = Struct.new(:to, :subject, :body, keyword_init: true)

    module_function

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
            body: {text: {data: message.body, charset: "UTF-8"}}
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
