class ApiError < StandardError
  attr_reader :code, :status, :details

  # @param code [Symbol] a key in {ErrorCodes::REGISTRY}
  # @param details [Array<Hash>] field-level problems, each with :field and :message
  def initialize(code, details: [])
    definition = ErrorCodes::REGISTRY.fetch(code)
    @code = code
    @status = definition[:status]
    @details = details
    super(definition[:default_message])
  end

  def to_h
    { error: { code: code, message: message, details: details } }
  end
end
