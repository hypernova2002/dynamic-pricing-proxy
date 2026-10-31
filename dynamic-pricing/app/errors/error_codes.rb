module ErrorCodes
  REGISTRY = {
    validation_failed: { status: 422, default_message: "One or more parameters are invalid." },
    pricing_upstream_error: { status: 502, default_message: "The pricing service returned an unexpected response. Please try again." },
    pricing_upstream_timeout: { status: 504, default_message: "The pricing service took too long to respond. Please try again." },
    pricing_unavailable: { status: 503, default_message: "Rates are temporarily unavailable. Please try again later." },
    internal_error: { status: 500, default_message: "An unexpected error occurred." }
  }.freeze
end
