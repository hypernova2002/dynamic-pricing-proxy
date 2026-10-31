require "rails_helper"

RSpec.describe RateApiClient do
  let(:url) { "#{described_class.base_uri}/pricing" }
  let(:attributes) { [ { period: "Summer", hotel: "GitawayHotel", room: "BooleanTwin" } ] }
  let(:rows) { [ { "period" => "Summer", "hotel" => "GitawayHotel", "room" => "BooleanTwin", "rate" => 12000 } ] }

  describe ".get_rates" do
    context "when the API succeeds" do
      before { stub_request(:post, url).to_return(status: 200, body: { rates: rows }.to_json) }

      it "returns the rows" do
        expect(described_class.get_rates(attributes)).to eq(rows)
      end

      it "sends the attributes" do
        described_class.get_rates(attributes)
        expect(a_request(:post, url).with(body: { attributes: attributes }.to_json)).to have_been_made.once
      end

      it "sends the token" do
        described_class.get_rates(attributes)
        expect(a_request(:post, url).with(headers: { "token" => ENV.fetch("RATE_API_TOKEN") })).to have_been_made
      end
    end

    it "sets timeouts, because the API can hang indefinitely" do
      expect(described_class.default_options).to include(open_timeout: 1, read_timeout: 2, write_timeout: 2)
    end

    it "raises a timeout error when the connection times out" do
      stub_request(:post, url).to_raise(Net::OpenTimeout)
      expect { described_class.get_rates(attributes) }.to raise_error(described_class::TimeoutError)
    end

    it "raises a timeout error when the read times out" do
      stub_request(:post, url).to_raise(Net::ReadTimeout)
      expect { described_class.get_rates(attributes) }.to raise_error(described_class::TimeoutError)
    end

    it "raises a quota error on HTTP 429" do
      stub_request(:post, url).to_return(status: 429, body: { error: "Rate limit exceeded (1000/day)" }.to_json)
      expect { described_class.get_rates(attributes) }.to raise_error(described_class::QuotaExceededError)
    end

    it "raises an error when the connection is refused" do
      stub_request(:post, url).to_raise(Errno::ECONNREFUSED)
      expect { described_class.get_rates(attributes) }.to raise_error(described_class::Error)
    end

    it "raises an error on HTTP 500" do
      stub_request(:post, url).to_return(status: 500, body: { error: "An unexpected internal error occurred" }.to_json)
      expect { described_class.get_rates(attributes) }.to raise_error(described_class::Error, "HTTP 500")
    end

    it "raises an error on HTTP 401" do
      stub_request(:post, url).to_return(status: 401, body: { error: "Unauthorized" }.to_json)
      expect { described_class.get_rates(attributes) }.to raise_error(described_class::Error, "HTTP 401")
    end

    it "raises an error on an HTML error page" do
      stub_request(:post, url).to_return(status: 400, body: "<h1>Bad Request</h1>", headers: { "Content-Type" => "text/html" })
      expect { described_class.get_rates(attributes) }.to raise_error(described_class::Error, "HTTP 400")
    end

    it "raises an error on invalid JSON" do
      stub_request(:post, url).to_return(status: 200, body: "not json")
      expect { described_class.get_rates(attributes) }.to raise_error(described_class::Error, "Response is not valid JSON")
    end

    it "raises an error on an empty body" do
      stub_request(:post, url).to_return(status: 200, body: "")
      expect { described_class.get_rates(attributes) }.to raise_error(described_class::Error, "Response is not valid JSON")
    end

    it "raises an error when rates is missing" do
      stub_request(:post, url).to_return(status: 200, body: {}.to_json)
      expect { described_class.get_rates(attributes) }.to raise_error(described_class::Error, "Response has no rates array")
    end

    it "raises an error when the body is not an object" do
      stub_request(:post, url).to_return(status: 200, body: [].to_json)
      expect { described_class.get_rates(attributes) }.to raise_error(described_class::Error, "Response has no rates array")
    end
  end
end
