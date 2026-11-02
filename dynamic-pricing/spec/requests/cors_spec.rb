require "rails_helper"

RSpec.describe "CORS", type: :request do
  let(:origin) { { "Origin" => "https://app.example.com" } }

  context "with a request from another origin" do
    before { get api_v1_pricing_url, headers: origin }

    it "allows the origin" do
      expect(response.headers["access-control-allow-origin"]).to eq("*")
    end

    it "lets browsers read Retry-After" do
      expect(response.headers["access-control-expose-headers"]).to include("Retry-After")
    end

    it "lets browsers read the request ID" do
      expect(response.headers["access-control-expose-headers"]).to include("X-Request-Id")
    end
  end

  context "with a preflight request" do
    before do
      options api_v1_pricing_url, headers: origin.merge("Access-Control-Request-Method" => "GET")
    end

    it "allows GET" do
      expect(response.headers["access-control-allow-methods"]).to include("GET")
    end

    it "does not allow writes, because the API has none" do
      expect(response.headers["access-control-allow-methods"]).not_to include("POST")
    end
  end

  context "when a request is throttled" do
    before do
      Rack::Attack.enabled = true
      Rails.configuration.x.requests_per_minute = 3
      travel_to(Time.utc(2026, 1, 1, 12, 0, 0))
      4.times { get api_v1_pricing_url, headers: origin.merge("REMOTE_ADDR" => "203.0.113.9") }
    end

    it "is still readable by the browser" do
      expect(response.headers["access-control-allow-origin"]).to eq("*")
    end

    it "is the throttled response" do
      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
