require "rails_helper"

RSpec.describe Api::V1::PricingService do
  subject(:service) { described_class.new(period: "Summer", hotel: "GitawayHotel", room: "BooleanTwin") }

  let(:requested) { { "period" => "Summer", "hotel" => "GitawayHotel", "room" => "BooleanTwin" } }

  def stub_rows(*rows)
    allow(RateApiClient).to receive(:get_rates).and_return(rows)
  end

  describe "#run" do
    it "asks for all 36 combinations in one call" do
      stub_rows(requested.merge("rate" => 12000))
      service.run
      expect(RateApiClient).to have_received(:get_rates).once.with(
        satisfy { |attributes| attributes.uniq.size == 36 }
      )
    end

    it "returns the rate for the requested combination" do
      stub_rows(requested.merge("hotel" => "RecursionRetreat", "rate" => 1), requested.merge("rate" => 12000))
      service.run
      expect(service.result).to eq(12000)
    end

    it "converts a string rate to an integer" do
      stub_rows(requested.merge("rate" => "12000"))
      service.run
      expect(service.result).to eq(12000)
    end

    it "ignores invalid rows when the requested rate is valid" do
      stub_rows("not a row", requested.merge("hotel" => "RecursionRetreat", "rate" => "n/a"), requested.merge("rate" => 12000))
      service.run
      expect(service.result).to eq(12000)
    end

    [ nil, "", "n/a", "12.5", 12.5, 0, -100, [ 1 ] ].each do |rate|
      it "treats a rate of #{rate.inspect} as an upstream error" do
        stub_rows(requested.merge("rate" => rate))
        expect { service.run }.to raise_error(an_instance_of(ApiError).and(having_attributes(code: :pricing_upstream_error)))
      end
    end

    it "treats a missing combination as an upstream error" do
      stub_rows
      expect { service.run }.to raise_error(an_instance_of(ApiError).and(having_attributes(code: :pricing_upstream_error)))
    end

    context "when other combinations are missing" do
      before do
        allow(Rails.logger).to receive(:warn)
        stub_rows(requested.merge("rate" => 12000))
        service.run
      end

      it "still returns the requested rate" do
        expect(service.result).to eq(12000)
      end

      it "logs the missing combinations" do
        expect(Rails.logger).to have_received(:warn).with(
          a_string_including("rate_api_missing_rows", "RecursionRetreat")
        )
      end

      it "does not list the combination that was returned" do
        expect(Rails.logger).not_to have_received(:warn).with(
          a_string_including('["Summer","GitawayHotel","BooleanTwin"]')
        )
      end
    end

    context "when a combination is duplicated" do
      before do
        allow(Rails.logger).to receive(:warn)
        stub_rows(requested.merge("rate" => 1000), requested.merge("rate" => 2000))
        service.run
      end

      it "keeps the last rate" do
        expect(service.result).to eq(2000)
      end

      it "logs the duplicate" do
        expect(Rails.logger).to have_received(:warn).with(a_string_including("rate_api_duplicate_row"))
      end
    end

    context "when a row was not requested" do
      before do
        allow(Rails.logger).to receive(:warn)
        stub_rows(requested.merge("rate" => 12000), requested.merge("hotel" => "UnknownHotel", "rate" => 1))
        service.run
      end

      it "still returns the requested rate" do
        expect(service.result).to eq(12000)
      end

      it "logs the unexpected row" do
        expect(Rails.logger).to have_received(:warn).with(
          a_string_including("rate_api_unexpected_row", "UnknownHotel")
        )
      end
    end

    it "treats a row with no rate for the requested combination as missing" do
      stub_rows(requested)
      expect { service.run }.to raise_error(an_instance_of(ApiError).and(having_attributes(code: :pricing_upstream_error)))
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
