module ErrorCodes
  REGISTRY = {
    validation_failed: { status: 422, default_message: "One or more parameters are invalid." },
    rate_not_available: { status: 502, default_message: "No current rate is available for this room. Please try again shortly." },
    pricing_unavailable: { status: 503, default_message: "Rates are temporarily unavailable. Please try again shortly." },
    rate_limited: { status: 429, default_message: "Too many requests. Please try again shortly." },
    internal_error: { status: 500, default_message: "An unexpected error occurred." }
  }.freeze
end
