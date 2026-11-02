require "rails_helper"

RSpec.describe StructuredLog do
  let(:lines) { [] }
  let(:line) { JSON.parse(lines.last) }

  before do
    %i[info warn error].each do |level|
      allow(Rails.logger).to receive(level) { |message| lines << message }
    end
  end

  it "writes the event and fields as JSON" do
    described_class.info("something_happened", count: 2)
    expect(line).to include("event" => "something_happened", "count" => 2)
  end

  it "adds a UTC timestamp" do
    described_class.info("something_happened")
    expect(line["timestamp"]).to match(/Z\z/)
  end

  it "uses the requested level" do
    described_class.error("something_failed")
    expect(Rails.logger).to have_received(:error)
  end

  it "leaves out IDs that aren't set" do
    described_class.info("something_happened")
    expect(line.keys).not_to include("request_id", "refresh_id")
  end

  it "includes the current request ID" do
    Current.set(request_id: "req-1") { described_class.info("something_happened") }
    expect(line["request_id"]).to eq("req-1")
  end

  it "includes the current refresh ID" do
    Current.set(refresh_id: "ref-1") { described_class.info("something_happened") }
    expect(line["refresh_id"]).to eq("ref-1")
  end
end
