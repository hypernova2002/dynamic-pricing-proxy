module Pricing
  class IndexRequest < ApplicationRequestModel
    attribute :period, JsonModel::Types::String.enum("Summer", "Autumn", "Winter", "Spring")
    attribute :hotel, JsonModel::Types::String.enum("FloatingPointResort", "GitawayHotel", "RecursionRetreat")
    attribute :room, JsonModel::Types::String.enum("SingletonRoom", "BooleanTwin", "RestfulKing")
  end
end
