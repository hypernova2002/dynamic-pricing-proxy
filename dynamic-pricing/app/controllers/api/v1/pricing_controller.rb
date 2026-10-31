class Api::V1::PricingController < ApplicationController
  VALID_VALUES = {
    period: %w[Summer Autumn Winter Spring].freeze,
    hotel: %w[FloatingPointResort GitawayHotel RecursionRetreat].freeze,
    room: %w[SingletonRoom BooleanTwin RestfulKing].freeze
  }.freeze

  before_action :validate_params

  def index
    period = params[:period]
    hotel  = params[:hotel]
    room   = params[:room]

    service = Api::V1::PricingService.new(period:, hotel:, room:)
    service.run
    render json: { rate: service.result }
  end

  private

  def validate_params
    details = VALID_VALUES.filter_map do |field, values|
      if params[field].blank?
        { field: field, message: "is required" }
      elsif !values.include?(params[field])
        { field: field, message: "must be one of: #{values.join(', ')}" }
      end
    end

    raise ApiError.new(:validation_failed, details: details) if details.any?
  end
end
