module Schemas
  class ErrorResponse
    include OpenapiRuby::Components::Base

    schema(
      type: :object,
      required: %w[error],
      additionalProperties: false,
      properties: {
        error: {
          type: :object,
          required: %w[code message details],
          additionalProperties: false,
          properties: {
            code: {
              type: :string,
              enum: ErrorCodes::REGISTRY.keys.map(&:to_s),
              description: "A stable, machine-readable code."
            },
            message: { type: :string, description: "A summary that is safe to show to users." },
            details: {
              type: :array,
              description: "Field-level problems. Empty when the error isn't about a specific field.",
              items: {
                type: :object,
                required: %w[field message],
                additionalProperties: false,
                properties: {
                  field: { type: :string },
                  message: { type: :string }
                }
              }
            }
          }
        }
      }
    )
  end
end
