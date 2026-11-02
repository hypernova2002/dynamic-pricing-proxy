require "rails_helper"

RSpec.describe "Request logging", type: :request do
  let(:params) { { period: "Summer", hotel: "GitawayHotel", room: "BooleanTwin" } }
  let(:log_lines) { [] }
  let(:request_log) do
    log_lines.filter_map { |line| JSON.parse(line) rescue nil }.find { |line| line["event"] == "http_request" }
  end

  before do
    allow(Rails.logger).to receive(:info) { |message = nil, &block| log_lines << (message || block&.call) }
  end

  context "with a successful request" do
    before do
      Pricing::RateSnapshot.store(rates: { [ "Summer", "GitawayHotel", "BooleanTwin" ] => 12000 }, fetched_at: Time.current)
      get api_v1_pricing_url, params: params
    end

    it "logs one JSON line for the request" do
      expect(log_lines.count { |line| line.to_s.include?("http_request") }).to eq(1)
    end

    it "logs the status and timing" do
      expect(request_log).to include("method" => "GET", "path" => "/api/v1/pricing", "status" => 200, "duration" => a_kind_of(Numeric))
    end

    it "logs the same request ID that the client receives" do
      expect(request_log["request_id"]).to eq(response.headers["X-Request-Id"])
    end

    it "logs the request parameters" do
      expect(request_log["params"]).to eq("period" => "Summer", "hotel" => "GitawayHotel", "room" => "BooleanTwin")
    end

    it "logs a UTC timestamp" do
      expect(request_log["timestamp"]).to match(/Z\z/)
    end

    it "does not log an error code" do
      expect(request_log).not_to have_key("error_code")
    end
  end

  context "with a failed request" do
    before { get api_v1_pricing_url, params: params }

    it "logs the error code" do
      expect(request_log).to include("status" => 503, "error_code" => "pricing_unavailable")
    end
  end

  context "with invalid parameters" do
    before { get api_v1_pricing_url, params: params.merge(hotel: "Nope") }

    it "logs the error code" do
      expect(request_log["error_code"]).to eq("validation_failed")
    end

    it "logs the rejected value, so the failure can be diagnosed" do
      expect(request_log.dig("params", "hotel")).to eq("Nope")
    end
  end
end
