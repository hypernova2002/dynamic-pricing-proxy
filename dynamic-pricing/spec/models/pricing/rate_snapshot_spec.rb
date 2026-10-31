require "rails_helper"

RSpec.describe Pricing::RateSnapshot do
  let(:key) { [ "Summer", "GitawayHotel", "BooleanTwin" ] }
  let(:rates) { { key => 12000 } }
  let(:start) { Time.utc(2026, 1, 1, 12, 0, 0) }

  before { travel_to(start) }

  describe ".current" do
    it "returns nothing when no snapshot is stored" do
      expect(described_class.current).to be_nil
    end

    it "returns the stored rates" do
      described_class.store(rates: rates, fetched_at: start)
      expect(described_class.current.rates).to eq(rates)
    end

    it "returns when the rates were fetched" do
      described_class.store(rates: rates, fetched_at: start)
      expect(described_class.current.fetched_at).to eq(start)
    end

    it "returns the snapshot just before five minutes" do
      described_class.store(rates: rates, fetched_at: start)
      travel_to(start + 299.seconds)
      expect(described_class.current).not_to be_nil
    end

    it "returns nothing at exactly five minutes" do
      described_class.store(rates: rates, fetched_at: start)
      travel_to(start + 300.seconds)
      expect(described_class.current).to be_nil
    end

    it "measures expiry from when the fetch started, not when it was stored" do
      travel_to(start + 10.seconds)
      described_class.store(rates: rates, fetched_at: start)
      travel_to(start + 300.seconds)
      expect(described_class.current).to be_nil
    end

    it "rejects an expired entry even if the cache still returns it" do
      allow(Rails.cache).to receive(:read).and_return({ entries: {}, fetched_at: start - 300.seconds })
      expect(described_class.current).to be_nil
    end
  end

  describe ".store" do
    it "does not cache rates that are already expired" do
      described_class.store(rates: rates, fetched_at: start - 300.seconds)
      expect(Rails.cache.read(described_class::CACHE_KEY)).to be_nil
    end

    context "when a later fetch omits a row" do
      let(:other_key) { [ "Winter", "GitawayHotel", "BooleanTwin" ] }

      before do
        described_class.store(rates: { key => 12000, other_key => 5000 }, fetched_at: start)
        travel_to(start + 180.seconds)
        described_class.store(rates: { other_key => 6000 }, fetched_at: Time.current)
      end

      it "keeps the omitted row's earlier rate" do
        expect(described_class.current.rates[key]).to eq(12000)
      end

      it "replaces the row that was returned" do
        expect(described_class.current.rates[other_key]).to eq(6000)
      end

      it "keeps the omitted row just before its own five minutes end" do
        travel_to(start + 299.seconds)
        expect(described_class.current.rates[key]).to eq(12000)
      end

      it "drops the omitted row at its own five minutes, not the snapshot's" do
        travel_to(start + 300.seconds)
        expect(described_class.current.rates).not_to have_key(key)
      end

      it "keeps the newer row after the omitted one has expired" do
        travel_to(start + 300.seconds)
        expect(described_class.current.rates[other_key]).to eq(6000)
      end

      it "does not bring back an expired row in a later fetch" do
        travel_to(start + 300.seconds)
        described_class.store(rates: { other_key => 7000 }, fetched_at: Time.current)
        expect(described_class.current.rates).not_to have_key(key)
      end
    end
  end

  describe "#rate_for" do
    subject(:snapshot) do
      described_class.new(entries: { key => { rate: 12000, fetched_at: start } }, fetched_at: start)
    end

    it "returns the rate for a known combination" do
      expect(snapshot.rate_for(period: "Summer", hotel: "GitawayHotel", room: "BooleanTwin")).to eq(12000)
    end

    it "returns nothing for a missing combination" do
      expect(snapshot.rate_for(period: "Winter", hotel: "GitawayHotel", room: "BooleanTwin")).to be_nil
    end

    it "returns nothing once the rate's own window has ended" do
      travel_to(start + 300.seconds)
      expect(snapshot.rate_for(period: "Summer", hotel: "GitawayHotel", room: "BooleanTwin")).to be_nil
    end
  end
end
