Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    allowed_origins = case Rails.env
    when "development"
      [ "http://localhost:5173" ]
    when "production", "staging"
      [
        "http://localhost:5173/",
        "https://attorney-staffing-portal-frontend.onrender.com/",
      ]
    when "test"
      [ "http://localhost:5173" ]
    end

    origins allowed_origins

    resource "*",
             headers: :any,
             methods: %i[ get post put patch delete options head ],
             expose: [ "Authorization" ],
             credentials: true
  end
end
