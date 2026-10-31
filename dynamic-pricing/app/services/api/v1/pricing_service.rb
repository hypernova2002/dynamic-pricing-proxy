module Api::V1
  class PricingService < BaseService
    ALL_ATTRIBUTES = Pricing::IndexRequest::PERIODS
      .product(Pricing::IndexRequest::HOTELS, Pricing::IndexRequest::ROOMS)
      .map { |period, hotel, room| { period: period, hotel: hotel, room: room } }
      .freeze
    ALL_KEYS = ALL_ATTRIBUTES.map(&:values).to_set.freeze

    def initialize(period:, hotel:, room:)
      @period = period
      @hotel = hotel
      @room = room
    end

    def run
      @result = fetch_rates[[ @period, @hotel, @room ]]
      raise ApiError.new(:pricing_upstream_error) if @result.nil?
    end

    private

    def fetch_rates
      rates = build_rates(RateApiClient.get_rates(ALL_ATTRIBUTES))
      missing = ALL_KEYS - rates.keys
      log_warning("rate_api_missing_rows", rows: missing.to_a) if missing.any?
      rates
    rescue RateApiClient::TimeoutError
      raise ApiError.new(:pricing_upstream_timeout)
    rescue RateApiClient::QuotaExceededError
      raise ApiError.new(:pricing_unavailable)
    rescue RateApiClient::Error
      raise ApiError.new(:pricing_upstream_error)
    end

    # Rows have no identifiers, so they can only be matched by their values.
    def build_rates(rows)
      rows.each_with_object({}) do |row, rates|
        rate = parse_rate(row)
        next log_warning("rate_api_invalid_row", row: row) if rate.nil?

        key = row.values_at("period", "hotel", "room")
        next log_warning("rate_api_unexpected_row", row: row) unless ALL_KEYS.include?(key)

        log_warning("rate_api_duplicate_row", row: row) if rates.key?(key)
        rates[key] = rate
      end
    end

    # The API documents rates as strings but returns integers, so accept both.
    def parse_rate(row)
      return unless row.is_a?(Hash)

      rate = Integer(row["rate"].to_s, 10, exception: false)
      rate if rate&.positive?
    end

    def log_warning(event, **fields)
      Rails.logger.warn({ event: event, **fields }.to_json)
    end
  end
end
