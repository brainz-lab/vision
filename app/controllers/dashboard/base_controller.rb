module Dashboard
  class BaseController < ApplicationController
    layout 'dashboard'

    helper_method :current_project

    private

    def set_project
      @project = Project.find(params[:project_id])
    end

    def current_project
      @project
    end
  end
end
