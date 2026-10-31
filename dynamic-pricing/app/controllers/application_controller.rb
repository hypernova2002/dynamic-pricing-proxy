class ApplicationController < ActionController::API
  rescue_from StandardError, with: :render_internal_error
  rescue_from ApiError, with: :render_api_error

  private

  def render_api_error(error)
    render json: { error: { code: error.code, message: error.message, details: error.details } }, status: error.status
  end

  def render_internal_error(exception)
    Rails.logger.error("#{exception.class}: #{exception.message}")
    render_api_error(ApiError.new(:internal_error))
  end
end
