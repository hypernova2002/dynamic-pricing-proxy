require "rails_helper"

RSpec.describe Api::V1::PricingService do
  subject(:service) { described_class.new(period: "Summer", hotel: "GitawayHotel", room: "BooleanTwin") }

  let(:key) { [ "Summer", "GitawayHotel", "BooleanTwin" ] }

  before { allow(RateApiClient).to receive(:get_rates) }

  describe "#run" do
    context "with a valid snapshot" do
      before do
        Pricing::RateSnapshot.store(rates: { key => 12000 }, fetched_at: Time.current)
        service.run
      end

      it "returns the cached rate" do
        expect(service.result).to eq(12000)
      end

      it "does not call the API" do
        expect(RateApiClient).not_to have_received(:get_rates)
      end
    end

    context "when the snapshot lacks the requested combination" do
      before { Pricing::RateSnapshot.store(rates: { [ "Winter", "GitawayHotel", "BooleanTwin" ] => 1 }, fetched_at: Time.current) }

      it "reports that the rate isn't available" do
        expect { service.run }.to raise_error(an_instance_of(ApiError).and(having_attributes(code: :rate_not_available)))
      end

      it "does not call the API" do
        begin
          service.run
        rescue ApiError
          nil
        end
        expect(RateApiClient).not_to have_received(:get_rates)
      end
    end

    context "without a snapshot" do
      it "reports that rates are unavailable" do
        expect { service.run }.to raise_error(an_instance_of(ApiError).and(having_attributes(code: :pricing_unavailable)))
      end

      it "does not call the API" do
        begin
          service.run
        rescue ApiError
          nil
        end
        expect(RateApiClient).not_to have_received(:get_rates)
      end
    end
  end
end
