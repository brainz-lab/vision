module Dashboard
  class ComparisonsController < BaseController
    before_action :set_project
    before_action :set_comparison, only: [ :show, :approve, :reject ]

    def index
      @comparisons = Comparison.includes(:page, :baseline, :snapshot)
                               .joins(:page)
                               .where(pages: { project_id: @project.id })
                               .order(created_at: :desc)
                               .limit(50)
    end

    def show
      @baseline = @comparison.baseline
      @snapshot = @comparison.snapshot
    end

    def approve
      update_baseline = params[:update_baseline] == "1"
      user_email = session[:user_email] || "dashboard@brainzlab.ai"

      @comparison.approve!(user_email, update_baseline: update_baseline)

      redirect_to dashboard_project_comparison_path(@project, @comparison), notice: "Comparison approved"
    end

    def reject
      user_email = session[:user_email] || "dashboard@brainzlab.ai"
      notes = params[:notes]

      @comparison.reject!(user_email, notes: notes)

      redirect_to dashboard_project_comparison_path(@project, @comparison), notice: "Comparison rejected"
    end

    private

    def set_comparison
      @comparison = Comparison.joins(:page).where(pages: { project_id: @project.id }).find(params[:id])
    end
  end
end
