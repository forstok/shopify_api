module ShopifyAPI
  class Connection < ActiveResource::Connection
    attr_reader :response

    module ResponseCapture
      def handle_response(response)
        @response = super
      end
    end

    include ResponseCapture

    module RequestNotification
      def request(method, path, *arguments)
        super.tap do |response|
          notify_about_request(method, path, response, arguments)
        end
      rescue => e
        notify_about_request(method, path, e.response, arguments) if e.respond_to?(:response)
        raise
      end

      def notify_about_request(method, path, response, arguments)
        warn_deprecation_to_slack(method, path, response, arguments)

        ActiveSupport::Notifications.instrument("request.active_resource_detailed") do |payload|
          payload[:method]   = method
          payload[:path]     = path
          payload[:response] = response
          payload[:data]     = arguments
        end
      end

      def warn_deprecation_to_slack(method, path, response, arguments)
        response.each do |header_name, header_value|
          case header_name.downcase
          when 'x-shopify-api-deprecated-reason'
            warning_message = <<~MSG
              [DEPRECATED] ShopifyAPI made a call to #{method} #{path}, and this call made
              use of a deprecated endpoint, behaviour, or parameter. See #{header_name}: #{header_value} for more details.
            MSG

            warn warning_message

            notifier = Slack::Notifier.new ENV['SLACK_WEBHOOK_URL'] do
              defaults channel: "#deprecated-api", username: "notifier"
            end

            notifier.ping(<<-NOTIFIER.squeeze(' '))
              *Message*
              #{warning_message}

              *Arguments*
              ```
              #{arguments}
              ```
            NOTIFIER
          end
        end
      end
    end

    include RequestNotification
  end
end
