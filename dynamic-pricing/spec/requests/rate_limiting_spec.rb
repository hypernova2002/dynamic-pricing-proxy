require "rails_helper"

RSpec.describe "Rate limiting", type: :request do
  let(:params) { { period: "Summer", hotel: "GitawayHotel", room: "BooleanTwin" } }
  let(:start) { Time.utc(2026, 1, 1, 12, 0, 0) }
  let(:client_ip) { { "REMOTE_ADDR" => "203.0.113.1" } }

  before do
    Rack::Attack.enabled = true
    travel_to(start)
    Pricing::RateSnapshot.store(rates: { [ "Summer", "GitawayHotel", "BooleanTwin" ] => 12000 }, fetched_at: start)
  end

  def request_times(count, headers: client_ip)
    count.times { get api_v1_pricing_url, params: params, headers: headers }
  end

  it "allows 300 requests a minute from one IP" do
    request_times(300)
    expect(response).to have_http_status(:ok)
  end

  context "when an IP goes over the limit" do
    before { request_times(301) }

    it "returns too many requests" do
      expect(response).to have_http_status(:too_many_requests)
    end

    it "returns JSON" do
      expect(response.media_type).to eq("application/json")
    end

    it "uses the standard error format" do
      expect(JSON.parse(response.body)).to eq(
        "error" => {
          "code" => "rate_limited",
          "message" => "Too many requests. Please try again shortly.",
          "details" => []
        }
      )
    end

    it "says when to retry" do
      expect(response.headers["retry-after"].to_i).to be_between(1, 60)
    end

    it "does not affect another IP" do
      request_times(1, headers: { "REMOTE_ADDR" => "203.0.113.2" })
      expect(response).to have_http_status(:ok)
    end

    it "allows requests again in the next period" do
      travel_to(start + 1.minute)
      Pricing::RateSnapshot.store(rates: { [ "Summer", "GitawayHotel", "BooleanTwin" ] => 12000 }, fetched_at: Time.current)
      request_times(1)
      expect(response).to have_http_status(:ok)
    end
  end

  context "when Redis is unavailable to the throttle" do
    around do |example|
      original_store = Rack::Attack.cache.store
      Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
        url: "redis://localhost:1/0",
        connect_timeout: 0.1,
        reconnect_attempts: 0
      )
      example.run
      Rack::Attack.cache.store = original_store
    end

    it "lets the request through" do
      request_times(1)
      expect(response).to have_http_status(:ok)
    end
  end
end
