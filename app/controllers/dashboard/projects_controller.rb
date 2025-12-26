module Dashboard
  class ProjectsController < BaseController
    skip_before_action :require_authentication, only: [:index]

    def index
      @projects = Project.all.order(created_at: :desc)
    end

    def new
      @project = Project.new
    end

    def create
      @project = Project.new(project_params)
      @project.platform_project_id ||= "vis_#{SecureRandom.hex(8)}"

      if @project.save
        session[:project_id] = @project.id
        redirect_to dashboard_project_pages_path(@project), notice: 'Project created'
      else
        render :new, status: :unprocessable_entity
      end
    end

    def pages
      @project = Project.find(params[:id])
      @pages = @project.pages.ordered
    end

    def test_runs
      @project = Project.find(params[:id])
      @test_runs = @project.test_runs.recent.limit(50)
    end

    def settings
      @project = Project.find(params[:id])
    end

    private

    def project_params
      params.require(:project).permit(:name, :base_url, :staging_url)
    end
  end
end
