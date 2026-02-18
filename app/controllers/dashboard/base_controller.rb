module Dashboard
  class BaseController < ApplicationController
    layout "dashboard"

    before_action :authenticate_via_sso!

    helper_method :current_project

    private

    def authenticate_via_sso!
      return if Rails.env.development?

      unless session[:platform_project_id]
        platform_url = ENV.fetch("BRAINZLAB_PLATFORM_EXTERNAL_URL", "https://platform.brainzlab.ai")
        redirect_to "#{platform_url}/auth/sso?product=vision&return_to=#{request.url}", allow_other_host: true
      end
    end

    def set_project
      @project = Project.find(params[:project_id])
    end

    def current_project
      @project
    end
  end
end
