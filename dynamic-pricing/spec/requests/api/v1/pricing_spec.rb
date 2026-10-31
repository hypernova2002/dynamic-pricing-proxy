require "rails_helper"

RSpec.describe "Api::V1::Pricing", type: :request do
  let(:valid_params) { { period: "Summer", hotel: "FloatingPointResort", room: "SingletonRoom" } }
  let(:json_response) { JSON.parse(response.body) }
  let(:error) { json_response["error"] }

  describe "GET /api/v1/pricing" do
    context "when the rate API succeeds" do
      let(:rate_response) do
        double(
          success?: true,
          body: { "rates" => [ valid_params.transform_keys(&:to_s).merge("rate" => "15000") ] }.to_json
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

      it "returns only the rate" do
        expect(json_response).to eq("rate" => "15000")
      end
    end

    context "when the rate API returns an error" do
      let(:rate_response) { double(success?: false, body: { "error" => "Unauthorized" }.to_json) }

      before do
        allow(RateApiClient).to receive(:get_rate).and_return(rate_response)
        get api_v1_pricing_url, params: valid_params
      end

      it "returns bad gateway" do
        expect(response).to have_http_status(:bad_gateway)
      end

      it "returns the upstream error code" do
        expect(error["code"]).to eq("pricing_upstream_error")
      end

      it "does not expose the upstream message" do
        expect(response.body).not_to include("Unauthorized")
      end
    end

    context "when the rate API omits the requested rate" do
      let(:rate_response) { double(success?: true, body: { "rates" => [] }.to_json) }

      before do
        allow(RateApiClient).to receive(:get_rate).and_return(rate_response)
        get api_v1_pricing_url, params: valid_params
      end

      it "returns bad gateway" do
        expect(response).to have_http_status(:bad_gateway)
      end

      it "returns the upstream error code" do
        expect(error["code"]).to eq("pricing_upstream_error")
      end
    end

    context "when an unexpected error occurs" do
      before do
        allow(RateApiClient).to receive(:get_rate).and_raise(StandardError, "secret internal detail")
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

    context "with several invalid parameters" do
      before { get api_v1_pricing_url, params: { period: "Summer", hotel: "InvalidHotel" } }

      it "reports all of them together" do
        expect(error["details"].map { |detail| detail["field"] }).to contain_exactly("hotel", "room")
      end
    end
  end
end
