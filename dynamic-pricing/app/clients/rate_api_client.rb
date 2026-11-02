class RateApiClient
  include HTTParty

  class Error < StandardError; end
  class TimeoutError < Error; end
  class QuotaExceededError < Error; end

  CONNECTION_ERRORS = [ SocketError, SystemCallError, IOError, HTTParty::Error ].freeze
  TIMEOUT_ERRORS = [ Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout ].freeze

  base_uri ENV.fetch("RATE_API_URL", "http://localhost:8080")
  headers "Content-Type" => "application/json"
  headers "token" => ENV.fetch("RATE_API_TOKEN")
  open_timeout 1
  read_timeout 2
  write_timeout 2

  # @param attributes [Array<Hash>] the :period, :hotel and :room of each rate to fetch
  # @return [Array] the rows of the response's rates array, not yet validated
  # @raise [TimeoutError] if the pricing model doesn't respond in time
  # @raise [QuotaExceededError] if the daily quota is used up
  # @raise [Error] on any other failure
  def self.get_rates(attributes)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = post("/pricing", body: { attributes: attributes }.to_json)
    log_request(started_at, status: response.code)
    parse(response)
  rescue *TIMEOUT_ERRORS => e
    log_request(started_at, error: e.class.name)
    raise TimeoutError, e.message
  rescue *CONNECTION_ERRORS => e
    log_request(started_at, error: e.class.name)
    raise Error, e.message
  end

  def self.parse(response)
    raise QuotaExceededError, "HTTP 429" if response.code == 429
    raise Error, "HTTP #{response.code}" unless response.success?

    rates = JSON.parse(response.body.to_s).then { |body| body["rates"] if body.is_a?(Hash) }
    raise Error, "Response has no rates array" unless rates.is_a?(Array)

    rates
  rescue JSON::ParserError
    raise Error, "Response is not valid JSON"
  end
  private_class_method :parse

  def self.log_request(started_at, **fields)
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
    StructuredLog.info("rate_api_request", duration_ms: duration_ms, **fields)
  end
  private_class_method :log_request
end
