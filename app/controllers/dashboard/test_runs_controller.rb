module Dashboard
  class TestRunsController < BaseController
    before_action :set_project
    before_action :set_test_run, only: [:show]

    def index
      @test_runs = @project.test_runs.recent.limit(50)
    end

    def show
      @comparisons = @test_run.comparisons.includes(:page, :baseline, :snapshot).order(created_at: :desc)
    end

    def create
      @test_run = @project.test_runs.build(
        name: params[:name] || "Test Run #{Time.current.strftime('%Y-%m-%d %H:%M')}",
        status: 'pending'
      )

      if @test_run.save
        redirect_to dashboard_project_test_run_path(@project, @test_run), notice: 'Test run started'
      else
        redirect_to dashboard_project_test_runs_path(@project), alert: 'Failed to create test run'
      end
    end

    private

    def set_test_run
      @test_run = @project.test_runs.find(params[:id])
    end
  end
end
