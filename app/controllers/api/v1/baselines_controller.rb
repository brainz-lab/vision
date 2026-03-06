module Api
  module V1
    class BaselinesController < BaseController
      before_action :set_baseline, only: [:show, :approve, :reject]

      # GET /api/v1/baselines
      def index
        baselines = current_project.baselines.recent

        baselines = baselines.where(page_id: params[:page_id]) if params[:page_id]
        baselines = baselines.where(active: true) if params[:active].present?
        baselines = baselines.limit(params[:limit] || 50)

        render json: {
          baselines: baselines.map { |b| serialize_baseline(b) }
        }
      end

      # GET /api/v1/baselines/:id
      def show
        render json: serialize_baseline(@baseline)
      end

      # POST /api/v1/baselines/:id/approve
      def approve
        @baseline.approve!(current_user_email)

        render json: {
          message: "Baseline approved",
          baseline: serialize_baseline(@baseline)
        }
      end

      # POST /api/v1/baselines/:id/reject
      def reject
        @baseline.update!(active: false)

        render json: {
          message: "Baseline rejected",
          baseline: serialize_baseline(@baseline)
        }
      end

      private

      def current_user_email
        params[:user_email] || @key_info[:user_email] || "api@vision.brainzlab.ai"
      end

      def set_baseline
        @baseline = current_project.baselines.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Baseline not found" }, status: :not_found
      end

      def serialize_baseline(baseline)
        {
          id: baseline.id,
          page_id: baseline.page_id,
          page_name: baseline.page.name,
          browser_config_id: baseline.browser_config_id,
          browser_config_name: baseline.browser_config.name,
          branch: baseline.branch,
          commit_sha: baseline.commit_sha,
          environment: baseline.environment,
          active: baseline.active,
          width: baseline.width,
          height: baseline.height,
          file_size: baseline.file_size,
          approved_at: baseline.approved_at,
          approved_by: baseline.approved_by,
          screenshot_url: baseline.screenshot_url,
          thumbnail_url: baseline.thumbnail_url,
          created_at: baseline.created_at
        }
      end
    end
  end
end
