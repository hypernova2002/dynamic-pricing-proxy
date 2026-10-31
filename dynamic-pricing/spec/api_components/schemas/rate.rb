module Schemas
  class Rate
    include OpenapiRuby::Components::Base

    schema(
      type: :object,
      required: %w[rate],
      additionalProperties: false,
      properties: {
        rate: { type: :integer, minimum: 1, description: "The room rate, no more than five minutes old." }
      }
    )
  end
end
