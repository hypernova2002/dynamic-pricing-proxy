class Api::V1::PricingController < ApplicationController
  def index
    input = parse_request(Pricing::IndexRequest, request.query_parameters)

    service = Api::V1::PricingService.new(**input.to_h)
    service.run
    render json: Pricing::RateSerializer.new({ rate: service.result })
  end
end
