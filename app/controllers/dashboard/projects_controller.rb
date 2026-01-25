module Dashboard
  class ProjectsController < BaseController
    before_action :set_project, only: [ :show, :edit, :update, :settings ]
    before_action :redirect_to_platform_in_production, only: [ :new, :create ]

    def index
      # Load projects eagerly to prevent separate EXISTS query from .any? check
      # Counter cache columns (pages_count, test_runs_count) eliminate N+1 queries
      @projects = Project.order(created_at: :desc).load
    end

    def show
      redirect_to dashboard_project_pages_path(@project)
    end

    def new
      @project = Project.new
    end

    def create
      @project = Project.new(project_params)
      @project.platform_project_id ||= "vis_#{SecureRandom.hex(8)}"

      if @project.save
        redirect_to dashboard_project_pages_path(@project), notice: "Project created"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @project.update(project_params)
        redirect_to dashboard_project_pages_path(@project), notice: "Project updated"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def settings
    end

    private

    def set_project
      @project = Project.find(params[:id])
    end

    def project_params
      params.require(:project).permit(:name, :base_url, :staging_url)
    end

    def redirect_to_platform_in_production
      return unless Rails.env.production?

      platform_url = ENV.fetch("BRAINZLAB_PLATFORM_EXTERNAL_URL", "https://platform.brainzlab.ai")
      redirect_to dashboard_projects_path, alert: "Projects are managed in Platform. Visit #{platform_url} to create new projects."
    end
  end
end
