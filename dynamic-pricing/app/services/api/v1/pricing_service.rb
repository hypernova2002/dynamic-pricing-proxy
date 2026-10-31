module Api::V1
  class PricingService < BaseService
    def initialize(period:, hotel:, room:)
      @period = period
      @hotel = hotel
      @room = room
    end

    # Only ever reads the cache. The worker is the only caller of the rate API,
    # so traffic can't affect how much of the quota is used.
    def run
      snapshot = Pricing::RateSnapshot.current
      raise ApiError.new(:pricing_unavailable) if snapshot.nil?

      @result = snapshot.rate_for(period: @period, hotel: @hotel, room: @room)
      raise ApiError.new(:rate_not_available) if @result.nil?
    end
  end
end
