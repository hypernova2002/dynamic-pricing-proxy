module ErrorCodes
  REGISTRY = {
    validation_failed: { status: 422, default_message: "One or more parameters are invalid." },
    pricing_upstream_error: { status: 502, default_message: "The pricing service returned an unexpected response. Please try again." },
    internal_error: { status: 500, default_message: "An unexpected error occurred." }
  }.freeze
end
