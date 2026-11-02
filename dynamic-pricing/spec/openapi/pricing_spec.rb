require "openapi_helper"

RSpec.describe "Pricing API", type: :openapi do
  path "/api/v1/pricing" do
    get "Get a room rate" do
      tags "Pricing"
      operationId "getPricing"
      produces "application/json"
      description "Returns the current rate for a room. Rates come from a cache kept up to date by a " \
        "background worker, so requests never call the pricing model directly."

      parameter name: :period, in: :query, required: true, schema: { type: :string, enum: Pricing::IndexRequest::PERIODS }
      parameter name: :hotel, in: :query, required: true, schema: { type: :string, enum: Pricing::IndexRequest::HOTELS }
      parameter name: :room, in: :query, required: true, schema: { type: :string, enum: Pricing::IndexRequest::ROOMS }

      let(:period) { "Summer" }
      let(:hotel) { "GitawayHotel" }
      let(:room) { "BooleanTwin" }
      let(:valid_key) { [ period, hotel, room ] }

      response 200, "The current rate" do
        schema Schemas::Rate

        before { Pricing::RateSnapshot.store(rates: { valid_key => 12000 }, fetched_at: Time.current) }

        run_test! do
          expect(parsed_body).to eq("rate" => 12000)
        end
      end

      response 422, "A parameter is missing, invalid or not recognized (validation_failed)" do
        schema Schemas::ErrorResponse

        let(:period) { "Monsoon" }

        run_test! do
          expect(parsed_body.dig("error", "code")).to eq("validation_failed")
        end
      end

      response 429, "Too many requests from this IP (rate_limited)" do
        schema Schemas::ErrorResponse
        header "Retry-After", schema: { type: :integer }, description: "Seconds until requests are allowed again."

        before do
          Rack::Attack.enabled = true
          Rails.configuration.x.requests_per_minute = 3
          travel_to(Time.utc(2026, 1, 1, 12, 0, 0))
          3.times { get "/api/v1/pricing", params: { period: period, hotel: hotel, room: room } }
        end

        run_test! do
          expect(parsed_body.dig("error", "code")).to eq("rate_limited")
        end
      end

      response 500, "An unexpected error (internal_error)" do
        schema Schemas::ErrorResponse

        before { allow(Pricing::RateSnapshot).to receive(:current).and_raise(StandardError) }

        run_test! do
          expect(parsed_body.dig("error", "code")).to eq("internal_error")
        end
      end

      response 502, "No current rate for this room, while other rates are available (rate_not_available)" do
        schema Schemas::ErrorResponse

        before { Pricing::RateSnapshot.store(rates: { [ "Winter", hotel, room ] => 12000 }, fetched_at: Time.current) }

        run_test! do
          expect(parsed_body.dig("error", "code")).to eq("rate_not_available")
        end
      end

      response 503, "No current rates are available (pricing_unavailable)" do
        schema Schemas::ErrorResponse

        run_test! do
          expect(parsed_body.dig("error", "code")).to eq("pricing_unavailable")
        end
      end
    end
  end

  it "documents every registered error code" do
    documented = File.read(__FILE__).scan(/\((\w+)\)"/).flatten
    expect(documented).to match_array(ErrorCodes::REGISTRY.keys.map(&:to_s))
  end
end
