module Dashboard
  class BaseController < ApplicationController
    before_action :require_authentication

    helper_method :current_project

    private

    def require_authentication
      unless session[:project_id]
        # In development, auto-authenticate
        if Rails.env.development?
          session[:project_id] = Project.first&.id || create_dev_project.id
        else
          redirect_to root_path, alert: 'Please sign in'
        end
      end
    end

    def current_project
      @current_project ||= Project.find(session[:project_id])
    end

    def create_dev_project
      Project.create!(
        platform_project_id: 'dev_project',
        name: 'Development Project',
        base_url: 'http://localhost:3000'
      )
    end
  end
end
