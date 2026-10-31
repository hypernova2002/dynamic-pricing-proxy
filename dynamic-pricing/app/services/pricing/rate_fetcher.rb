module Pricing
  class RateFetcher
    ALL_ATTRIBUTES = IndexRequest::PERIODS
      .product(IndexRequest::HOTELS, IndexRequest::ROOMS)
      .map { |period, hotel, room| { period: period, hotel: hotel, room: room } }
      .freeze
    ALL_KEYS = ALL_ATTRIBUTES.map(&:values).to_set.freeze

    # Fetches every rate in one upstream call and stores the valid ones.
    #
    # @return [RateSnapshot]
    # @raise [RateApiClient::Error] if the call fails or returns no valid rates,
    #   leaving any stored snapshot in place
    def call
      # The API gives no timestamps, so a rate's age can only be measured from before the call.
      fetched_at = Time.current
      rates = build_rates(RateApiClient.get_rates(ALL_ATTRIBUTES))
      raise RateApiClient::Error, "Response has no valid rates" if rates.empty?

      missing = ALL_KEYS - rates.keys
      log_warning("rate_api_missing_rows", rows: missing.to_a) if missing.any?
      RateSnapshot.store(rates: rates, fetched_at: fetched_at)
    end

    private

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
