module Dashboard
  class PagesController < BaseController
    before_action :set_project
    before_action :set_page, only: [ :show, :edit, :update, :destroy ]

    def index
      @pages = @project.pages.includes(:latest_snapshot).ordered
    end

    def show
      @baselines = @page.baselines.includes(:browser_config).with_attached_screenshot.recent
      @snapshots = @page.snapshots.includes(:browser_config).with_attached_screenshot.recent.limit(20)
    end

    def new
      @page = @project.pages.build
    end

    def create
      @page = @project.pages.build(page_params)

      if @page.save
        redirect_to dashboard_project_page_path(@project, @page), notice: "Page created"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @page.update(page_params)
        redirect_to dashboard_project_page_path(@project, @page), notice: "Page updated"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @page.destroy
      redirect_to dashboard_project_pages_path(@project), notice: "Page deleted"
    end

    private

    def set_page
      @page = @project.pages.find(params[:id])
    end

    def page_params
      params.require(:page).permit(
        :name, :path, :wait_for, :wait_ms,
        :hide_selectors, :mask_selectors, :enabled,
        viewport: [ :width, :height ]
      )
    end
  end
end
