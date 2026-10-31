require "rails_helper"

RSpec.describe Api::V1::PricingService do
  subject(:service) { described_class.new(period: "Summer", hotel: "GitawayHotel", room: "BooleanTwin") }

  let(:requested) { { "period" => "Summer", "hotel" => "GitawayHotel", "room" => "BooleanTwin" } }
  let(:key) { [ "Summer", "GitawayHotel", "BooleanTwin" ] }

  def stub_rows(*rows)
    allow(RateApiClient).to receive(:get_rates).and_return(rows)
  end

  describe "#run" do
    context "with a valid snapshot" do
      before do
        Pricing::RateSnapshot.store(rates: { key => 12000 }, fetched_at: Time.current)
        stub_rows
      end

      it "returns the cached rate" do
        service.run
        expect(service.result).to eq(12000)
      end

      it "does not call the API" do
        service.run
        expect(RateApiClient).not_to have_received(:get_rates)
      end
    end

    context "when the snapshot lacks the requested combination" do
      before do
        Pricing::RateSnapshot.store(rates: { [ "Winter", "GitawayHotel", "BooleanTwin" ] => 1 }, fetched_at: Time.current)
        stub_rows
      end

      it "treats it as an upstream error" do
        expect { service.run }.to raise_error(an_instance_of(ApiError).and(having_attributes(code: :pricing_upstream_error)))
      end

      it "does not call the API again" do
        begin
          service.run
        rescue ApiError
          nil
        end
        expect(RateApiClient).not_to have_received(:get_rates)
      end
    end

    context "without a snapshot" do
      it "fetches and returns the rate" do
        stub_rows(requested.merge("rate" => 12000))
        service.run
        expect(service.result).to eq(12000)
      end

      {
        RateApiClient::TimeoutError => :pricing_upstream_timeout,
        RateApiClient::QuotaExceededError => :pricing_unavailable,
        RateApiClient::Error => :pricing_upstream_error
      }.each do |client_error, code|
        it "maps #{client_error} to #{code}" do
          allow(RateApiClient).to receive(:get_rates).and_raise(client_error)
          expect { service.run }.to raise_error(an_instance_of(ApiError).and(having_attributes(code: code)))
        end
      end
    end
  end
end
