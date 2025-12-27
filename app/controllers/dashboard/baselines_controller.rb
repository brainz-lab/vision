module Dashboard
  class BaselinesController < BaseController
    before_action :set_project

    def index
      @baselines = Baseline.includes(:page, :browser_config)
                           .with_attached_screenshot
                           .with_attached_thumbnail
                           .joins(:page)
                           .where(pages: { project_id: @project.id })
                           .order(created_at: :desc)
                           .limit(50)
    end

    def show
      @baseline = Baseline.joins(:page).where(pages: { project_id: @project.id }).find(params[:id])
      @page = @baseline.page
    end
  end
end
