require "rails_helper"

RSpec.describe "Cache store error handling" do
  let(:store) do
    ActiveSupport::Cache::RedisCacheStore.new(
      url: "redis://localhost:1/0",
      connect_timeout: 0.1,
      reconnect_attempts: 0,
      error_handler: Interview::Application::CACHE_ERROR_HANDLER
    )
  end

  it "raises on a failed read rather than reporting a cache miss" do
    expect { store.read("key") }.to raise_error(Redis::BaseError)
  end

  it "raises on a failed write rather than reporting failure quietly" do
    expect { store.write("key", "value") }.to raise_error(Redis::BaseError)
  end
end
