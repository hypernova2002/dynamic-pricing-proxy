module Pricing
  class IndexRequest < ApplicationRequestModel
    PERIODS = %w[Summer Autumn Winter Spring].freeze
    HOTELS = %w[FloatingPointResort GitawayHotel RecursionRetreat].freeze
    ROOMS = %w[SingletonRoom BooleanTwin RestfulKing].freeze

    attribute :period, JsonModel::Types::String.enum(*PERIODS)
    attribute :hotel, JsonModel::Types::String.enum(*HOTELS)
    attribute :room, JsonModel::Types::String.enum(*ROOMS)
  end
end
