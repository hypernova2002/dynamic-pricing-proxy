module Pricing
  class RateSnapshot
    CACHE_KEY = "pricing:rate_snapshot".freeze
    VALIDITY = 5.minutes

    attr_reader :fetched_at

    # @return [RateSnapshot, nil] the stored snapshot, if it is still valid
    def self.current
      entry = Rails.cache.read(CACHE_KEY)
      return if entry.nil?

      snapshot = new(**entry)
      snapshot unless snapshot.expired?
    end

    # Rows missing from this fetch keep their earlier rate until that rate's own window ends.
    # The cache entry expires when the newest rates do, measured from fetched_at rather than from now.
    #
    # @param rates [Hash{Array<String> => Integer}] rates keyed by [period, hotel, room]
    # @param fetched_at [Time] when the upstream call was sent
    # @return [RateSnapshot]
    def self.store(rates:, fetched_at:)
      new_entries = rates.transform_values { |rate| { rate: rate, fetched_at: fetched_at } }
      entries = (current&.valid_entries || {}).merge(new_entries)
      snapshot = new(entries: entries, fetched_at: fetched_at)
      remaining = VALIDITY - snapshot.age
      Rails.cache.write(CACHE_KEY, { entries: entries, fetched_at: fetched_at }, expires_in: remaining) if remaining.positive?
      snapshot
    end

    def initialize(entries:, fetched_at:)
      @entries = entries
      @fetched_at = fetched_at
    end

    def age
      Time.current - fetched_at
    end

    def expired?
      age >= VALIDITY
    end

    def valid_entries
      @entries.select { |_key, entry| Time.current - entry[:fetched_at] < VALIDITY }
    end

    # @return [Hash{Array<String> => Integer}] the rates still within their own window
    def rates
      valid_entries.transform_values { |entry| entry[:rate] }
    end

    def rate_for(period:, hotel:, room:)
      rates[[ period, hotel, room ]]
    end
  end
end
