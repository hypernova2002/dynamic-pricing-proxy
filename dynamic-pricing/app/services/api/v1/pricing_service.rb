module Api::V1
  class PricingService < BaseService
    def initialize(period:, hotel:, room:)
      @period = period
      @hotel = hotel
      @room = room
    end

    def run
      # TODO: Start to implement here
      rate = RateApiClient.get_rate(period: @period, hotel: @hotel, room: @room)
      raise ApiError.new(:pricing_upstream_error) unless rate.success?

      parsed_rate = JSON.parse(rate.body)
      @result = parsed_rate["rates"].detect { |r| r["period"] == @period && r["hotel"] == @hotel && r["room"] == @room }&.dig("rate")
      raise ApiError.new(:pricing_upstream_error) if @result.nil?
    end
  end
end
