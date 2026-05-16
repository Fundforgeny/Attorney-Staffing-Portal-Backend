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
      resources :plans, only: [ :create, :show ], param: :checkout_session_id
      post "plans/:checkout_session_id/generate_agreement", to: "plans#generate_agreement"
      post "plans/:checkout_session_id/mark_payment_success", to: "plans#mark_payment_success"
      post "plans/:checkout_session_id/mark_payment_failed", to: "plans#mark_payment_failed"
      post "plans/:checkout_session_id/cancel_payment", to: "plans#cancel_payment"
      patch "customer/plans/:id/next_payment_at", to: "plans#update_next_payment_at"
      resources :payment_methods, only: [ :index, :show, :create, :update, :destroy ] do
        post :set_default, on: :member
      end

      namespace :auth do
        resource :login_link, only: [ :create, :show ], controller: "login_links"
      end

      namespace :workflows do
        resources :client_case_intakes, only: [:create]
      end

      post 'payments/create_user_plan', to: 'payments#create_user_plan'
      get 'payments/iframe_security', to: 'payments#iframe_security'
      post 'magic_links/create_user_with_magic_link', to: 'magic_links#create_user_with_magic_link'
      post 'payments/checkout', to: 'payments#checkout'
      post 'payments/process_payment', to: 'payments#process_payment'
      post "payments/3ds/start", to: "payment_3ds#start"
      post "payments/3ds/complete", to: "payment_3ds#complete"
      post "payments/3ds/start_checkout", to: "payment_3ds#start_checkout"
      post "payments/3ds/complete_checkout", to: "payment_3ds#complete_checkout"
      post "payments/3ds/callback", to: "payment_3ds#callback"
      # post 'payments/create_payment_session', to: 'payments#create_payment_session'
      # post 'payments/create_verification_session', to: 'payments#create_verification_session'
      post 'payments/save_signature', to: 'payments#save_signature'
      post 'stripe_webhooks', to: 'stripe_webhooks#receive'
      post 'stripe_webhooks/update_payment_status', to: 'stripe_webhooks#update_payment_status'
      post 'magic_links/validate', to: 'magic_links#validate'

      # ── Admin API (JWT-authenticated) ──────────────────────────────────────
      namespace :admin do
        # Auth
        post "auth/sign_in", to: "auth#sign_in"
        resource :login_link, only: [ :create, :show ], controller: "login_links"

        # Dashboard
        get "dashboard", to: "dashboard#index"

        # Plans
        resources :plans, only: [:index, :show] do
          member do
            post :sync_ghl
            post :manual_charge
            post :charge_payment
            post :set_default_card
            delete :delete_card
            post :approve_grace_week
            post :deny_grace_week
          end
        end

        # Payments
        resources :payments, only: [:index, :show] do
          member do
            post :charge_now
            post :refund
          end
        end

        # Users
        resources :users, only: [:index, :show]

        # Staffing / matter management
        resources :cases, only: [:index, :show]
        resources :staffing_requirements, only: [:index, :show]

        # Admin Users
        resources :admin_users, only: [:index, :create, :show, :update]

        # Leads (non-paid plans)
        resources :leads, only: [:index]

        # Grace Week Queue
        resources :grace_week_requests, only: [:index, :show] do
          member do
            post :approve
            post :deny
          end
        end
      end

      # Customer-facing payment portal endpoints (JWT-authenticated)
      namespace :customer do
        get "me", to: "users#me"
        resources :plans, only: [] do
          member do
            get  :terms
            get  :invoices
          end
          resources :payments, only: [] do
            collection do
              get  :history
              post :manual_payment
            end
          end
          resources :grace_week_requests, only: [:create] do
            collection do
              get :status
            end
          end
        end
      end
    end
  end

  # Spreedly Account Updater batch callback
  # Configure this URL in the Spreedly dashboard: POST /webhooks/spreedly/account_updater
  namespace :webhooks do
    namespace :spreedly do
      post :account_updater, to: "spreedly_account_updater#create"
    end

    # Chargeflow webhook receiver
    # Configure this URL in the Chargeflow dashboard: POST /webhooks/chargeflow
    # Handles: alerts.created, dispute.created
    post :chargeflow, to: "chargeflow#receive"
  end

  require "sidekiq/web"
  authenticate :admin_user do
    mount Sidekiq::Web => "/sidekiq"
  end
end
