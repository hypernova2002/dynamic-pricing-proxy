module Pricing
  class RateRefresher
    REFRESH_AFTER = 180.seconds
    # At most one call per gate period caps usage at 960 calls a day, within the API's limit
    # of 1,000, however often this runs and whether or not the calls succeed.
    GATE_PERIOD = 90.seconds
    GATE_KEY = "pricing:rate_refresh_gate".freeze

    def initialize(fetcher: RateFetcher.new)
      @fetcher = fetcher
    end

    # Refreshes the rates if they are due and the gate allows a call. Never raises,
    # so that one failure can't stop the worker's loop.
    def tick
      return unless refresh_due?
      return unless acquire_gate

      refresh
    rescue StandardError => e
      log(:error, "rate_refresh_error", error: e.class.name)
    end

    private

    def refresh_due?
      snapshot = RateSnapshot.current
      snapshot.nil? || snapshot.age >= REFRESH_AFTER
    end

    def acquire_gate
      Rails.cache.write(GATE_KEY, true, unless_exist: true, expires_in: GATE_PERIOD)
    end

    def refresh
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      snapshot = @fetcher.call
      log(:info, "rate_refresh_succeeded", rates: snapshot.rates.size, duration_ms: elapsed_ms(started_at))
    rescue RateApiClient::Error => e
      log(:info, "rate_refresh_failed", error: e.class.name, message: e.message, duration_ms: elapsed_ms(started_at))
    end

    def elapsed_ms(started_at)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
    end

    def log(level, event, **fields)
      Rails.logger.public_send(level, { event: event, **fields }.to_json)
    end
  end
end
