Rails.application.routes.draw do
  devise_for :admin_users, ActiveAdmin::Devise.config
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  root to: redirect("/admin")
  ActiveAdmin.routes(self)

  get "up" => "rails/health#show", as: :rails_health_check

  # Devise for users (API routes)
  devise_for :users,
    controllers: {
      sessions: "users/sessions",
      registrations: "users/registrations",
      confirmations: "users/confirmations",
      passwords: "users/passwords",
      unlocks: "users/unlocks"
    },
    path: "api/v1",
    defaults: { format: :json },
    skip: [ :registrations, :sessions, :passwords, :confirmations, :unlocks ]

  # Admin login routes (using User model with super_admin type) - defined BEFORE Active Admin
  devise_scope :user do
    get "/admin/login", to: "admin/sessions#new", as: :new_admin_session
    post "/admin/login", to: "admin/sessions#create", as: :admin_session
    get "/admin/logout", to: "admin/sessions#destroy", as: :destroy_admin_session
  end 

  # config/routes.rb
  namespace :api do
    namespace :v1 do
      post 'payments/create_user_plan', to: 'payments#create_user_plan'
      post 'magic_links/create_user_with_magic_link', to: 'magic_links#create_user_with_magic_link'
      post 'payments/checkout', to: 'payments#checkout'
      post 'payments/process_payment', to: 'payments#process_payment'
      # post 'payments/create_payment_session', to: 'payments#create_payment_session'
      # post 'payments/create_verification_session', to: 'payments#create_verification_session'
      post 'payments/save_signature', to: 'payments#save_signature'
      post 'stripe_webhooks', to: 'stripe_webhooks#receive'
      post 'stripe_webhooks/update_payment_status', to: 'stripe_webhooks#update_payment_status'
      post 'magic_links/validate', to: 'magic_links#validate'
    end
  end

  require "sidekiq/web"
  authenticate :admin_user do
    mount Sidekiq::Web => "/sidekiq"
  end
end
