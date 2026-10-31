require "rails_helper"

RSpec.describe Pricing::RateFetcher do
  subject(:fetcher) { described_class.new }

  let(:requested) { { "period" => "Summer", "hotel" => "GitawayHotel", "room" => "BooleanTwin" } }
  let(:key) { [ "Summer", "GitawayHotel", "BooleanTwin" ] }

  def stub_rows(*rows)
    allow(RateApiClient).to receive(:get_rates).and_return(rows)
  end

  describe "#call" do
    it "asks for all 36 combinations in one call" do
      stub_rows(requested.merge("rate" => 12000))
      fetcher.call
      expect(RateApiClient).to have_received(:get_rates).once.with(
        satisfy { |attributes| attributes.uniq.size == 36 }
      )
    end

    it "stores the rates" do
      stub_rows(requested.merge("rate" => 12000))
      fetcher.call
      expect(Pricing::RateSnapshot.current.rates).to eq(key => 12000)
    end

    it "matches rows by their values, whatever their order" do
      stub_rows(requested.merge("hotel" => "RecursionRetreat", "rate" => 1), requested.merge("rate" => 12000))
      expect(fetcher.call.rates[key]).to eq(12000)
    end

    it "converts a string rate to an integer" do
      stub_rows(requested.merge("rate" => "12000"))
      expect(fetcher.call.rates[key]).to eq(12000)
    end

    it "records the time before the call, because the API gives no timestamps" do
      start = Time.utc(2026, 1, 1, 12, 0, 0)
      travel_to(start)
      allow(RateApiClient).to receive(:get_rates) do
        travel_to(start + 2.seconds)
        [ requested.merge("rate" => 12000) ]
      end
      expect(fetcher.call.fetched_at).to eq(start)
    end

    [ nil, "", "n/a", "12.5", 12.5, 0, -100, [ 1 ] ].each do |rate|
      it "skips a rate of #{rate.inspect}" do
        stub_rows(requested.merge("rate" => rate), requested.merge("hotel" => "RecursionRetreat", "rate" => 1))
        expect(fetcher.call.rates).not_to have_key(key)
      end
    end

    it "keeps the earlier rate when a later fetch returns an invalid row for it" do
      Pricing::RateSnapshot.store(rates: { key => 1000 }, fetched_at: Time.current)
      stub_rows(requested.merge("rate" => "n/a"), requested.merge("hotel" => "RecursionRetreat", "rate" => 1))
      expect(fetcher.call.rates[key]).to eq(1000)
    end

    it "skips a row that is not an object" do
      stub_rows("not a row", requested.merge("rate" => 12000))
      expect(fetcher.call.rates).to eq(key => 12000)
    end

    context "when no rows are valid" do
      before do
        Pricing::RateSnapshot.store(rates: { key => 1000 }, fetched_at: Time.current)
        stub_rows(requested.merge("rate" => "n/a"))
      end

      it "raises an error" do
        expect { fetcher.call }.to raise_error(RateApiClient::Error, "Response has no valid rates")
      end

      it "keeps the stored snapshot" do
        begin
          fetcher.call
        rescue RateApiClient::Error
          nil
        end
        expect(Pricing::RateSnapshot.current.rates).to eq(key => 1000)
      end
    end

    context "when the API call fails" do
      before do
        Pricing::RateSnapshot.store(rates: { key => 1000 }, fetched_at: Time.current)
        allow(RateApiClient).to receive(:get_rates).and_raise(RateApiClient::TimeoutError)
      end

      it "raises the error" do
        expect { fetcher.call }.to raise_error(RateApiClient::TimeoutError)
      end

      it "keeps the stored snapshot" do
        begin
          fetcher.call
        rescue RateApiClient::Error
          nil
        end
        expect(Pricing::RateSnapshot.current.rates).to eq(key => 1000)
      end
    end

    context "when other combinations are missing" do
      before do
        allow(Rails.logger).to receive(:warn)
        stub_rows(requested.merge("rate" => 12000))
        fetcher.call
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
      end

      it "keeps the last rate" do
        expect(fetcher.call.rates[key]).to eq(2000)
      end

      it "logs the duplicate" do
        fetcher.call
        expect(Rails.logger).to have_received(:warn).with(a_string_including("rate_api_duplicate_row"))
      end
    end

    context "when a row was not requested" do
      before do
        allow(Rails.logger).to receive(:warn)
        stub_rows(requested.merge("rate" => 12000), requested.merge("hotel" => "UnknownHotel", "rate" => 1))
      end

      it "does not store it" do
        expect(fetcher.call.rates).to eq(key => 12000)
      end

      it "logs the unexpected row" do
        fetcher.call
        expect(Rails.logger).to have_received(:warn).with(
          a_string_including("rate_api_unexpected_row", "UnknownHotel")
        )
      end
    end
  end
end
