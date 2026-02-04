Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins 'https://attorney-staffing-portal-frontend.onrender.com',
            'https://attorney-staffing-portal-backend-1.onrender.com',
            'https://payments.fundforge.net',
            'http://localhost:5173',
            'http://127.0.0.1:5173'

    resource '*',
             headers: :any,
             methods: %i[get post put patch delete options head]
             # Optionally need to set below for the future API's that requires authorisation
             # expose: ['Authorization', 'X-Frame-Options', 'Content-Disposition'],
             # credentials: true
  end
end
