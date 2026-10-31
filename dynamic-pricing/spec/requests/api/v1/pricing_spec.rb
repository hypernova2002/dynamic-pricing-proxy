require "rails_helper"

RSpec.describe "Api::V1::Pricing", type: :request do
  let(:valid_params) { { period: "Summer", hotel: "FloatingPointResort", room: "SingletonRoom" } }
  let(:json_response) { JSON.parse(response.body) }

  describe "GET /api/v1/pricing" do
    context "when the rate API succeeds" do
      let(:rate_response) do
        double(
          success?: true,
          body: { "rates" => [valid_params.transform_keys(&:to_s).merge("rate" => "15000")] }.to_json
        )
      end

      before do
        allow(RateApiClient).to receive(:get_rate).and_return(rate_response)
        get api_v1_pricing_url, params: valid_params
      end

      it "returns success" do
        expect(response).to have_http_status(:ok)
      end

      it "returns JSON" do
        expect(response.media_type).to eq("application/json")
      end

      it "returns the rate" do
        expect(json_response["rate"]).to eq("15000")
      end
    end

    context "when the rate API fails" do
      let(:rate_response) { double(success?: false, body: { "error" => "Rate not found" }) }

      before do
        allow(RateApiClient).to receive(:get_rate).and_return(rate_response)
        get api_v1_pricing_url, params: valid_params
      end

      it "returns bad request" do
        expect(response).to have_http_status(:bad_request)
      end

      it "returns the error message" do
        expect(json_response["error"]).to include("Rate not found")
      end
    end

    context "without any parameters" do
      before { get api_v1_pricing_url }

      it "returns bad request" do
        expect(response).to have_http_status(:bad_request)
      end

      it "reports the missing parameters" do
        expect(json_response["error"]).to include("Missing required parameters")
      end
    end

    context "with empty parameters" do
      before { get api_v1_pricing_url, params: { period: "", hotel: "", room: "" } }

      it "returns bad request" do
        expect(response).to have_http_status(:bad_request)
      end

      it "reports the missing parameters" do
        expect(json_response["error"]).to include("Missing required parameters")
      end
    end

    context "with an invalid period" do
      before { get api_v1_pricing_url, params: valid_params.merge(period: "summer-2024") }

      it "returns bad request" do
        expect(response).to have_http_status(:bad_request)
      end

      it "reports the invalid period" do
        expect(json_response["error"]).to include("Invalid period")
      end
    end

    context "with an invalid hotel" do
      before { get api_v1_pricing_url, params: valid_params.merge(hotel: "InvalidHotel") }

      it "returns bad request" do
        expect(response).to have_http_status(:bad_request)
      end

      it "reports the invalid hotel" do
        expect(json_response["error"]).to include("Invalid hotel")
      end
    end

    context "with an invalid room" do
      before { get api_v1_pricing_url, params: valid_params.merge(room: "InvalidRoom") }

      it "returns bad request" do
        expect(response).to have_http_status(:bad_request)
      end

      it "reports the invalid room" do
        expect(json_response["error"]).to include("Invalid room")
      end
    end
  end
end
