Rails.application.routes.draw do
  # API
  namespace :api do
    namespace :v1 do
      # Projects (auto-provisioning)
      post 'projects/provision', to: 'projects#provision'
      get 'projects/lookup', to: 'projects#lookup'

      # Pages
      resources :pages, only: [:index, :show, :create, :update, :destroy]

      # Browser configs
      resources :browser_configs, only: [:index, :show, :create, :update, :destroy]

      # Snapshots
      resources :snapshots, only: [:index, :show, :create] do
        member do
          post :compare
        end
      end

      # Baselines
      resources :baselines, only: [:index, :show] do
        member do
          post :approve
          post :reject
        end
      end

      # Comparisons
      resources :comparisons, only: [:index, :show] do
        member do
          post :approve
          post :reject
          post :update_baseline
        end
      end

      # Test runs
      resources :test_runs, only: [:index, :show, :create]

      # Test cases
      resources :test_cases, only: [:index, :show, :create, :update, :destroy]
    end
  end

  # MCP Server
  namespace :mcp do
    get 'tools', to: 'tools#index'
    post 'tools/:name', to: 'tools#call'
    post 'rpc', to: 'tools#rpc'
  end

  # SSO from Platform
  get 'sso/callback', to: 'sso#callback'

  # Dashboard
  namespace :dashboard do
    root to: 'projects#index'

    resources :projects, only: [:index, :new, :create] do
      member do
        get 'pages'
        get 'test_runs'
        get 'settings'
      end
    end

    resources :pages, only: [:show, :edit, :update]
    resources :test_runs, only: [:show]
    resources :comparisons, only: [:show] do
      member do
        post :approve
        post :reject
      end
    end
    resources :baselines, only: [:index, :show]
  end

  # Health check
  get 'up' => 'rails/health#show', as: :rails_health_check

  # WebSocket
  mount ActionCable.server => '/cable'

  root 'dashboard/projects#index'
end
