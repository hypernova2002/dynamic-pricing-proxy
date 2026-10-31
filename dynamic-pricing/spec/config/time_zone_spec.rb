require "rails_helper"

RSpec.describe "Time zone" do
  it "uses UTC for application times" do
    expect(Time.zone.name).to eq("UTC")
  end
end
