module Api
  module V1
    class TestRunsController < BaseController
      before_action :set_test_run, only: [ :show ]

      # GET /api/v1/test_runs
      def index
        test_runs = current_project.test_runs.recent

        if params[:branch]
          test_runs = test_runs.for_branch(params[:branch])
        end

        if params[:status]
          test_runs = test_runs.where(status: params[:status])
        end

        test_runs = test_runs.limit(params[:limit] || 50)

        render json: {
          test_runs: test_runs.map { |tr| serialize_test_run(tr) }
        }
      end

      # GET /api/v1/test_runs/:id
      def show
        render json: serialize_test_run(@test_run, include_comparisons: true)
      end

      # POST /api/v1/test_runs
      def create
        test_run = TestRunner.run_for_project!(
          current_project,
          branch: params[:branch],
          commit_sha: params[:commit_sha],
          commit_message: params[:commit_message],
          environment: params[:environment] || "staging",
          triggered_by: params[:triggered_by] || "api",
          trigger_source: params[:trigger_source],
          pr_number: params[:pr_number],
          pr_url: params[:pr_url],
          base_branch: params[:base_branch] || "main"
        )

        track_usage!(test_run.total_pages)

        render json: serialize_test_run(test_run), status: :created
      end

      private

      def set_test_run
        @test_run = current_project.test_runs.find(params[:id])
      end

      def serialize_test_run(test_run, include_comparisons: false)
        data = {
          id: test_run.id,
          branch: test_run.branch,
          commit_sha: test_run.commit_sha,
          commit_message: test_run.commit_message,
          environment: test_run.environment,
          triggered_by: test_run.triggered_by,
          pr_number: test_run.pr_number,
          pr_url: test_run.pr_url,
          status: test_run.status,
          started_at: test_run.started_at,
          completed_at: test_run.completed_at,
          duration_ms: test_run.duration_ms,
          summary: test_run.summary,
          progress: test_run.progress,
          created_at: test_run.created_at
        }

        if include_comparisons
          data[:comparisons] = test_run.comparisons.includes(:snapshot, :baseline).map do |comp|
            {
              id: comp.id,
              page_name: comp.page.name,
              browser_config_name: comp.snapshot.browser_config.name,
              status: comp.status,
              diff_percentage: comp.diff_percentage,
              review_status: comp.review_status,
              snapshot_url: comp.snapshot.screenshot_url,
              baseline_url: comp.baseline.screenshot_url,
              diff_url: comp.diff_image_url
            }
          end
        end

        data
      end
    end
  end
end
