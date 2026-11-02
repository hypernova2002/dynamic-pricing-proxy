Rails.application.configure do
  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::Json.new
  config.lograge.custom_options = lambda do |event|
    response = event.payload[:response]
    error_code = JSON.parse(response.body).dig("error", "code") if response.status >= 400

    {
      event: "http_request",
      timestamp: Time.current.iso8601(3),
      request_id: event.payload[:request].request_id,
      error_code: error_code,
      params: event.payload[:params].except("controller", "action")
    }.compact
  end
end
