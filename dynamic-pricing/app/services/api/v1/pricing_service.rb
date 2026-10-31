module Api::V1
  class PricingService < BaseService
    def initialize(period:, hotel:, room:)
      @period = period
      @hotel = hotel
      @room = room
    end

    def run
      snapshot = Pricing::RateSnapshot.current || fetch_snapshot
      @result = snapshot.rate_for(period: @period, hotel: @hotel, room: @room)
      raise ApiError.new(:pricing_upstream_error) if @result.nil?
    end

    private

    def fetch_snapshot
      Pricing::RateFetcher.new.call
    rescue RateApiClient::TimeoutError
      raise ApiError.new(:pricing_upstream_timeout)
    rescue RateApiClient::QuotaExceededError
      raise ApiError.new(:pricing_unavailable)
    rescue RateApiClient::Error
      raise ApiError.new(:pricing_upstream_error)
    end
  end
end
