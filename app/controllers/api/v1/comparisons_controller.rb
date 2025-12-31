module Api
  module V1
    class ComparisonsController < BaseController
      before_action :set_comparison

      # GET /api/v1/comparisons/:id
      def show
        render json: serialize_comparison(@comparison)
      end

      # POST /api/v1/comparisons/:id/approve
      def approve
        @comparison.approve!(
          current_user_email,
          update_baseline: params[:update_baseline] == true
        )

        render json: {
          message: "Comparison approved",
          baseline_updated: params[:update_baseline] == true,
          comparison: serialize_comparison(@comparison)
        }
      end

      # POST /api/v1/comparisons/:id/reject
      def reject
        @comparison.reject!(current_user_email, notes: params[:notes])

        render json: {
          message: "Comparison rejected",
          comparison: serialize_comparison(@comparison)
        }
      end

      # POST /api/v1/comparisons/:id/update_baseline
      def update_baseline
        @comparison.snapshot.promote_to_baseline!
        @comparison.approve!(current_user_email)

        render json: {
          message: "Baseline updated",
          comparison: serialize_comparison(@comparison)
        }
      end

      private

      def set_comparison
        @comparison = Comparison.joins(snapshot: { page: :project })
                                .where(pages: { project_id: current_project.id })
                                .find(params[:id])
      end

      def current_user_email
        # In a real implementation, this would come from the authenticated user
        params[:user_email] || @key_info[:user_email] || "api@vision.brainzlab.ai"
      end

      def serialize_comparison(comparison)
        {
          id: comparison.id,
          page_name: comparison.page.name,
          browser_config_name: comparison.snapshot.browser_config.name,
          status: comparison.status,
          diff_percentage: comparison.diff_percentage,
          diff_pixels: comparison.diff_pixels,
          threshold_used: comparison.threshold_used,
          within_threshold: comparison.within_threshold,
          review_status: comparison.review_status,
          reviewed_at: comparison.reviewed_at,
          reviewed_by: comparison.reviewed_by,
          review_notes: comparison.review_notes,
          baseline: {
            id: comparison.baseline.id,
            screenshot_url: comparison.baseline.screenshot_url,
            branch: comparison.baseline.branch
          },
          snapshot: {
            id: comparison.snapshot.id,
            screenshot_url: comparison.snapshot.screenshot_url,
            branch: comparison.snapshot.branch
          },
          diff_image_url: comparison.diff_image_url,
          created_at: comparison.created_at
        }
      end
    end
  end
end
