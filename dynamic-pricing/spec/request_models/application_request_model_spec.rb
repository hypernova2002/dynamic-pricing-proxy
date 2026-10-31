require "rails_helper"

RSpec.describe ApplicationRequestModel do
  let(:model) do
    Class.new(described_class) do
      attribute :count, JsonModel::Types::Integer
      attribute :color, JsonModel::Types::String.enum("red", "blue")
      attribute? :note, JsonModel::Types::String
    end
  end

  describe ".errors_for" do
    it "returns nothing for valid input" do
      expect(model.errors_for("count" => 1, "color" => "red")).to be_empty
    end

    it "does not require an optional key" do
      expect(model.errors_for("count" => 1, "color" => "red").map { |error| error[:field] }).not_to include(:note)
    end

    it "reports a required key that is missing" do
      expect(model.errors_for("color" => "red")).to eq([ { field: :count, message: "is required" } ])
    end

    it "reports a required key that is empty" do
      expect(model.errors_for("count" => "", "color" => "red")).to eq([ { field: :count, message: "is required" } ])
    end

    it "reports the wrong type generically" do
      expect(model.errors_for("count" => "many", "color" => "red")).to eq([ { field: :count, message: "is invalid" } ])
    end

    it "lists the allowed values for an enum" do
      expect(model.errors_for("count" => 1, "color" => "green")).to eq(
        [ { field: :color, message: "must be one of: red, blue" } ]
      )
    end

    it "reports an invalid optional key" do
      expect(model.errors_for("count" => 1, "color" => "red", "note" => 5)).to eq(
        [ { field: :note, message: "is invalid" } ]
      )
    end

    it "reports an unknown key" do
      expect(model.errors_for("count" => 1, "color" => "red", "extra" => "x")).to eq(
        [ { field: :extra, message: "is not a recognized parameter" } ]
      )
    end

    it "reports every problem together" do
      expect(model.errors_for("color" => "green", "extra" => "x").map { |error| error[:field] }).to contain_exactly(
        :count, :color, :extra
      )
    end
  end
end
