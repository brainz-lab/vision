Rails.application.routes.draw do
  # API
  namespace :api do
    namespace :v1 do
      # Projects (auto-provisioning)
      post "projects/provision", to: "projects#provision"
      get "projects/lookup", to: "projects#lookup"

      # Pages
      resources :pages, only: [ :index, :show, :create, :update, :destroy ]

      # Browser configs
      resources :browser_configs, only: [ :index, :show, :create, :update, :destroy ]

      # Snapshots
      resources :snapshots, only: [ :index, :show, :create ] do
        member do
          post :compare
        end
      end

      # Baselines
      resources :baselines, only: [ :index, :show ] do
        member do
          post :approve
          post :reject
        end
      end

      # Comparisons
      resources :comparisons, only: [ :index, :show ] do
        member do
          post :approve
          post :reject
          post :update_baseline
        end
      end

      # Test runs
      resources :test_runs, only: [ :index, :show, :create ]

      # Test cases
      resources :test_cases, only: [ :index, :show, :create, :update, :destroy ]

      # AI Tasks
      resources :tasks, only: [ :index, :show, :create ] do
        member do
          post :stop
          get :steps
        end
      end

      # Browser Sessions
      resources :sessions, only: [ :index, :show, :create, :destroy ] do
        member do
          post :ai        # page.ai() - AI-powered action
          post :perform   # page.perform() - direct action
          post :extract   # page.extract() - data extraction
          get :screenshot
          get :state
        end
      end

      # Credentials (Vault integration)
      resources :credentials, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          post :test  # Test credential fetch from Vault
        end
      end
    end
  end

  # MCP Server
  namespace :mcp do
    get "tools", to: "tools#index"
    post "tools/:name", to: "tools#call"
    post "rpc", to: "tools#rpc"
  end

  # SSO from Platform
  get "sso/callback", to: "sso#callback"

  # Dashboard
  namespace :dashboard do
    root to: "projects#index"

    resources :projects, only: [ :index, :show, :new, :create, :edit, :update ] do
      resources :pages, only: [ :index, :show, :new, :create, :edit, :update, :destroy ]
      resources :test_runs, only: [ :index, :show, :create ]
      resources :baselines, only: [ :index, :show ]
      resources :comparisons, only: [ :index, :show ] do
        member do
          post :approve
          post :reject
        end
      end
      resources :ai_tasks, only: [ :index, :show ] do
        member do
          post :retry, action: :retry_task
        end
      end
      member do
        get :settings
        get :mcp_setup
        post :regenerate_mcp_token
      end
    end
  end

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # WebSocket
  mount ActionCable.server => "/cable"

  root "dashboard/projects#index"
end
