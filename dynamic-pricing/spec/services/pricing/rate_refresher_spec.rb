require "rails_helper"

RSpec.describe Pricing::RateRefresher do
  subject(:refresher) { described_class.new }

  let(:start) { Time.utc(2026, 1, 1, 12, 0, 0) }
  let(:key) { [ "Summer", "GitawayHotel", "BooleanTwin" ] }
  let(:rows) { [ { "period" => "Summer", "hotel" => "GitawayHotel", "room" => "BooleanTwin", "rate" => 12000 } ] }

  before { travel_to(start) }

  describe "#tick" do
    context "when the API succeeds" do
      before { allow(RateApiClient).to receive(:get_rates).and_return(rows) }

      it "fetches when there are no rates" do
        refresher.tick
        expect(Pricing::RateSnapshot.current.rates).to eq(key => 12000)
      end

      it "does not fetch while rates are under 180 seconds old" do
        Pricing::RateSnapshot.store(rates: { key => 1000 }, fetched_at: start - 179.seconds)
        refresher.tick
        expect(RateApiClient).not_to have_received(:get_rates)
      end

      it "fetches once rates reach 180 seconds, before they expire" do
        Pricing::RateSnapshot.store(rates: { key => 1000 }, fetched_at: start - 180.seconds)
        refresher.tick
        expect(Pricing::RateSnapshot.current.rates).to eq(key => 12000)
      end

      it "does not fetch while the gate is held" do
        Rails.cache.write(described_class::GATE_KEY, true, expires_in: 90.seconds)
        refresher.tick
        expect(RateApiClient).not_to have_received(:get_rates)
      end

      it "logs success at info" do
        allow(Rails.logger).to receive(:info)
        refresher.tick
        expect(Rails.logger).to have_received(:info).with(a_string_including("rate_refresh_succeeded"))
      end
    end

    context "when the API fails" do
      before { allow(RateApiClient).to receive(:get_rates).and_raise(RateApiClient::TimeoutError, "execution expired") }

      it "does not raise" do
        expect { refresher.tick }.not_to raise_error
      end

      it "logs the failed attempt at info" do
        allow(Rails.logger).to receive(:info)
        refresher.tick
        expect(Rails.logger).to have_received(:info).with(
          a_string_including("rate_refresh_failed", "RateApiClient::TimeoutError")
        )
      end

      it "does not try again within 90 seconds" do
        refresher.tick
        travel_to(start + 89.seconds)
        refresher.tick
        expect(RateApiClient).to have_received(:get_rates).once
      end

      it "tries again after 90 seconds" do
        refresher.tick
        travel_to(start + 90.seconds)
        refresher.tick
        expect(RateApiClient).to have_received(:get_rates).twice
      end

      it "keeps valid rates in place" do
        Pricing::RateSnapshot.store(rates: { key => 1000 }, fetched_at: start - 180.seconds)
        refresher.tick
        expect(Pricing::RateSnapshot.current.rates).to eq(key => 1000)
      end
    end

    context "when Redis is unavailable" do
      before do
        allow(RateApiClient).to receive(:get_rates)
        allow(Rails.cache).to receive(:read).and_raise(Redis::CannotConnectError)
      end

      it "does not raise" do
        expect { refresher.tick }.not_to raise_error
      end

      it "does not call the API, because the gate can't be checked" do
        refresher.tick
        expect(RateApiClient).not_to have_received(:get_rates)
      end

      it "logs the error" do
        allow(Rails.logger).to receive(:error)
        refresher.tick
        expect(Rails.logger).to have_received(:error).with(a_string_including("rate_refresh_error"))
      end
    end

    context "when the gate can't be written" do
      before do
        allow(RateApiClient).to receive(:get_rates)
        allow(Rails.cache).to receive(:write).and_raise(Redis::CannotConnectError)
      end

      it "does not call the API" do
        refresher.tick
        expect(RateApiClient).not_to have_received(:get_rates)
      end
    end

    it "lets only one of several concurrent workers call the API" do
      calls = Concurrent::AtomicFixnum.new
      allow(RateApiClient).to receive(:get_rates) do
        calls.increment
        rows
      end

      Array.new(10) { Thread.new { described_class.new.tick } }.each(&:join)

      expect(calls.value).to eq(1)
    end
  end

  describe "quota over a simulated day" do
    let(:ticks_per_day) { 1.day.to_i / 5 }
    let(:calls) { [] }

    def simulate_day
      ticks_per_day.times do |tick|
        travel_to(start + (tick * 5).seconds)
        refresher.tick
      end
    end

    it "stays under the limit when every call fails" do
      allow(RateApiClient).to receive(:get_rates) do
        calls << Time.current
        raise RateApiClient::Error, "HTTP 500"
      end
      simulate_day
      expect(calls.size).to be <= 960
    end

    it "stays under the limit with the measured failure rate" do
      random = Random.new(1234)
      allow(RateApiClient).to receive(:get_rates) do
        calls << Time.current
        raise RateApiClient::Error, "HTTP 500" if random.rand < 0.165

        rows
      end
      simulate_day
      expect(calls.size).to be <= 960
    end

    it "refreshes about every 180 seconds when every call succeeds" do
      allow(RateApiClient).to receive(:get_rates) do
        calls << Time.current
        rows
      end
      simulate_day
      expect(calls.size).to be_between(450, 480)
    end
  end
end
