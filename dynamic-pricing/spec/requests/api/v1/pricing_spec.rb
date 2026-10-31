require "rails_helper"

RSpec.describe "Api::V1::Pricing", type: :request do
  let(:valid_params) { { period: "Summer", hotel: "FloatingPointResort", room: "SingletonRoom" } }
  let(:valid_key) { [ "Summer", "FloatingPointResort", "SingletonRoom" ] }
  let(:json_response) { JSON.parse(response.body) }
  let(:error) { json_response["error"] }
  let!(:rate_api) { stub_request(:post, "#{RateApiClient.base_uri}/pricing") }

  describe "GET /api/v1/pricing" do
    context "with valid rates" do
      before do
        Pricing::RateSnapshot.store(rates: { valid_key => 15000 }, fetched_at: Time.current)
        get api_v1_pricing_url, params: valid_params
      end

      it "returns success" do
        expect(response).to have_http_status(:ok)
      end

      it "returns JSON" do
        expect(response.media_type).to eq("application/json")
      end

      it "returns only the rate" do
        expect(json_response).to eq("rate" => 15000)
      end

      it "does not call the rate API" do
        expect(rate_api).not_to have_been_requested
      end
    end

    context "when the requested rate is missing" do
      before do
        Pricing::RateSnapshot.store(rates: { [ "Winter", "GitawayHotel", "BooleanTwin" ] => 1 }, fetched_at: Time.current)
        get api_v1_pricing_url, params: valid_params
      end

      it "returns bad gateway" do
        expect(response).to have_http_status(:bad_gateway)
      end

      it "returns the rate error code" do
        expect(error["code"]).to eq("rate_not_available")
      end
    end

    context "when rates have expired" do
      let(:start) { Time.utc(2026, 1, 1, 12, 0, 0) }

      before do
        travel_to(start)
        Pricing::RateSnapshot.store(rates: { valid_key => 15000 }, fetched_at: start)
      end

      it "serves the rate just before five minutes" do
        travel_to(start + 299.seconds)
        get api_v1_pricing_url, params: valid_params
        expect(response).to have_http_status(:ok)
      end

      it "stops serving the rate at five minutes" do
        travel_to(start + 300.seconds)
        get api_v1_pricing_url, params: valid_params
        expect(response).to have_http_status(:service_unavailable)
      end
    end

    context "when no rates are cached" do
      before { get api_v1_pricing_url, params: valid_params }

      it "returns service unavailable" do
        expect(response).to have_http_status(:service_unavailable)
      end

      it "returns the unavailable error code" do
        expect(error["code"]).to eq("pricing_unavailable")
      end
    end

    it "never calls the rate API, however many requests miss the cache" do
      1000.times { get api_v1_pricing_url, params: valid_params }
      expect(rate_api).not_to have_been_requested
    end

    [ Redis::CannotConnectError, ConnectionPool::TimeoutError ].each do |redis_error|
      context "when the cache fails with #{redis_error}" do
        before do
          allow(Rails.cache).to receive(:read).and_raise(redis_error, "redis://secret-host")
          get api_v1_pricing_url, params: valid_params
        end

        it "returns service unavailable" do
          expect(response).to have_http_status(:service_unavailable)
        end

        it "returns the unavailable error code" do
          expect(error["code"]).to eq("pricing_unavailable")
        end

        it "does not expose the Redis details" do
          expect(response.body).not_to include("secret-host")
        end

        it "does not call the rate API" do
          expect(rate_api).not_to have_been_requested
        end
      end
    end

    context "when an unexpected error occurs" do
      before do
        allow(Pricing::RateSnapshot).to receive(:current).and_raise(StandardError, "secret internal detail")
        get api_v1_pricing_url, params: valid_params
      end

      it "returns internal server error" do
        expect(response).to have_http_status(:internal_server_error)
      end

      it "returns the internal error code" do
        expect(error["code"]).to eq("internal_error")
      end

      it "does not expose the exception message" do
        expect(response.body).not_to include("secret internal detail")
      end
    end

    context "without any parameters" do
      before { get api_v1_pricing_url }

      it "returns unprocessable content" do
        expect(response).to have_http_status(422)
      end

      it "returns the validation error code" do
        expect(error["code"]).to eq("validation_failed")
      end

      it "reports every missing field" do
        expect(error["details"]).to contain_exactly(
          { "field" => "period", "message" => "is required" },
          { "field" => "hotel", "message" => "is required" },
          { "field" => "room", "message" => "is required" }
        )
      end
    end

    context "with empty parameters" do
      before { get api_v1_pricing_url, params: { period: "", hotel: "", room: "" } }

      it "returns unprocessable content" do
        expect(response).to have_http_status(422)
      end

      it "reports every field as required" do
        expect(error["details"].map { |detail| detail["message"] }.uniq).to eq([ "is required" ])
      end
    end

    context "with an invalid period" do
      before { get api_v1_pricing_url, params: valid_params.merge(period: "summer-2024") }

      it "returns unprocessable content" do
        expect(response).to have_http_status(422)
      end

      it "reports the period with its allowed values" do
        expect(error["details"]).to eq(
          [ { "field" => "period", "message" => "must be one of: Summer, Autumn, Winter, Spring" } ]
        )
      end
    end

    context "with an invalid hotel" do
      before { get api_v1_pricing_url, params: valid_params.merge(hotel: "InvalidHotel") }

      it "returns unprocessable content" do
        expect(response).to have_http_status(422)
      end

      it "reports the hotel" do
        expect(error["details"].map { |detail| detail["field"] }).to eq([ "hotel" ])
      end
    end

    context "with an invalid room" do
      before { get api_v1_pricing_url, params: valid_params.merge(room: "InvalidRoom") }

      it "returns unprocessable content" do
        expect(response).to have_http_status(422)
      end

      it "reports the room" do
        expect(error["details"].map { |detail| detail["field"] }).to eq([ "room" ])
      end
    end

    context "with an unknown parameter" do
      before { get api_v1_pricing_url, params: valid_params.merge(hotle: "GitawayHotel") }

      it "returns unprocessable content" do
        expect(response).to have_http_status(422)
      end

      it "reports the unknown parameter" do
        expect(error["details"]).to eq(
          [ { "field" => "hotle", "message" => "is not a recognized parameter" } ]
        )
      end
    end

    context "with an array where a single value is expected" do
      before { get api_v1_pricing_url, params: valid_params.merge(period: [ "Summer" ]) }

      it "returns unprocessable content" do
        expect(response).to have_http_status(422)
      end

      it "reports the period" do
        expect(error["details"].map { |detail| detail["field"] }).to eq([ "period" ])
      end
    end

    context "with several invalid parameters" do
      before { get api_v1_pricing_url, params: { period: "Summer", hotel: "InvalidHotel" } }

      it "reports all of them together" do
        expect(error["details"].map { |detail| detail["field"] }).to contain_exactly("hotel", "room")
      end
    end
  end
end
