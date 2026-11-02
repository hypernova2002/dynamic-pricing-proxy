# Rails.cache re-raises Redis errors, which in middleware would become a raw 500. This store
# keeps the default handler, so throttling is skipped during an outage and the request
# reaches the controller, which returns the standard 503.
unless Rails.env.test?
  Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
    url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
    namespace: "dynamic_pricing"
  )
end

Rack::Attack.throttle("requests/ip", limit: ->(_request) { Rails.configuration.x.requests_per_minute }, period: 1.minute) { |request| request.ip }

Rack::Attack.throttled_responder = lambda do |request|
  error = ApiError.new(:rate_limited)
  match_data = request.env["rack.attack.match_data"]
  retry_after = match_data[:period] - (match_data[:epoch_time] % match_data[:period])

  [
    error.status,
    { "content-type" => "application/json", "retry-after" => retry_after.to_s },
    [ error.to_h.to_json ]
  ]
end
