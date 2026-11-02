class StructuredLog
  def self.info(event, **fields) = write(:info, event, fields)
  def self.warn(event, **fields) = write(:warn, event, fields)
  def self.error(event, **fields) = write(:error, event, fields)

  def self.write(level, event, fields)
    Rails.logger.public_send(level, {
      event: event,
      timestamp: Time.current.iso8601(3),
      request_id: Current.request_id,
      refresh_id: Current.refresh_id,
      **fields
    }.compact.to_json)
  end
  private_class_method :write
end
