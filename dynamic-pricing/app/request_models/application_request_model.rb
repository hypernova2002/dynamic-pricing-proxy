class ApplicationRequestModel < Dry::Struct
  include JsonModel::Schema

  transform_keys(&:to_sym)
  schema schema.strict

  # Dry::Struct raises on the first problem, in wording that exposes its internals.
  # This reports every problem in wording that is safe to show to clients.
  #
  # @param input [Hash] the raw parameters
  # @return [Array<Hash>] one :field and :message for each problem
  def self.errors_for(input)
    input = input.to_h.symbolize_keys
    unknown_keys = input.keys - schema.keys.map(&:name)

    schema.keys.filter_map { |key| key_error(key, input) } +
      unknown_keys.map { |field| { field: field, message: "is not a recognized parameter" } }
  end

  def self.key_error(key, input)
    return { field: key.name, message: "is required" } if key.required? && [ nil, "" ].include?(input[key.name])
    return if !input.key?(key.name) || key.type.try(input[key.name]).success?

    message = key.type.respond_to?(:values) ? "must be one of: #{key.type.values.join(', ')}" : "is invalid"
    { field: key.name, message: message }
  end
  private_class_method :key_error
end
