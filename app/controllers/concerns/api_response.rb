module ApiResponse
  extend ActiveSupport::Concern

  included do
    def render_success(data: nil, message: nil, status: :ok, meta: {})
      response = {}
      response[:message] = message if message.present?
      response[:data]    = data if data.present?
      response[:meta]    = meta if meta.present?

      render json: response, status: status
    end

    def render_error(errors: nil, message: nil, status: :unprocessable_entity)
      response = {}
      response[:message] = message if message.present?
      response[:errors]  = Array(errors) if errors.present?

      render json: response, status: status
    end
  end
end
