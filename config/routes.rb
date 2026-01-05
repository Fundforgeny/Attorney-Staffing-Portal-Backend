Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "home#index"

  ActiveAdmin.routes(self)

  get "/super_admin/sign_in", to: "super_admin/sessions#new", as: :super_admin_sign_in
  post "/super_admin/sign_in", to: "super_admin/sessions#create"
  delete "/super_admin/sign_out", to: "super_admin/sessions#destroy", as: :super_admin_sign_out

  devise_for :users, controllers: {
    sessions: "sessions"
  }

  # config/routes.rb
  namespace :api do
    namespace :v1 do
      post 'payments/create_user_plan', to: 'payments#create_user_plan'
      post 'payments/checkout', to: 'payments#checkout'
      post 'payments/create_verification_session', to: 'payments#create_verification_session'
      post '/stripe/webhooks', to: 'stripe_webhooks#create'
    end
  end
  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
