module Api
  module V1
    class SnapshotsController < BaseController
      before_action :set_page, only: [ :index, :create ]
      before_action :set_snapshot, only: [ :show, :compare ]

      # GET /api/v1/snapshots
      def index
        snapshots = if @page
          @page.snapshots.recent
        else
          current_project.snapshots.recent
        end

        snapshots = snapshots.limit(params[:limit] || 50)

        render json: {
          snapshots: snapshots.map { |s| serialize_snapshot(s) }
        }
      end

      # GET /api/v1/snapshots/:id
      def show
        render json: serialize_snapshot(@snapshot, include_comparison: true)
      end

      # POST /api/v1/snapshots
      def create
        page = @page || find_or_create_page
        browser_config = find_browser_config

        snapshot = page.snapshots.new(
          browser_config: browser_config,
          branch: params[:branch],
          commit_sha: params[:commit_sha],
          environment: params[:environment] || "staging",
          triggered_by: "api",
          status: "pending"
        )

        if snapshot.save
          # Queue the capture job
          CaptureScreenshotJob.perform_later(snapshot.id)
          track_usage!

          render json: serialize_snapshot(snapshot), status: :created
        else
          render json: { errors: snapshot.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/snapshots/:id/compare
      def compare
        if @snapshot.status != "captured"
          render json: { error: "Snapshot not yet captured" }, status: :unprocessable_entity
          return
        end

        # Queue comparison job
        CompareScreenshotsJob.perform_later(@snapshot.id)

        render json: {
          message: "Comparison queued",
          snapshot_id: @snapshot.id
        }
      end

      private

      def set_page
        @page = current_project.pages.find(params[:page_id]) if params[:page_id]
      end

      def set_snapshot
        @snapshot = current_project.snapshots.find(params[:id])
      end

      def find_or_create_page
        if params[:url]
          uri = URI.parse(params[:url])
          path = uri.path.presence || "/"
          name = params[:name] || path

          current_project.pages.find_or_create_by!(path: path) do |page|
            page.name = name
            page.slug = name.parameterize
          end
        else
          current_project.pages.find(params[:page_id])
        end
      end

      def find_browser_config
        if params[:browser_config_id]
          current_project.browser_configs.find(params[:browser_config_id])
        else
          current_project.browser_configs.enabled.first ||
            current_project.browser_configs.first
        end
      end

      def serialize_snapshot(snapshot, include_comparison: false)
        data = {
          id: snapshot.id,
          page_id: snapshot.page_id,
          page_name: snapshot.page.name,
          browser_config_id: snapshot.browser_config_id,
          browser_config_name: snapshot.browser_config.name,
          branch: snapshot.branch,
          commit_sha: snapshot.commit_sha,
          environment: snapshot.environment,
          status: snapshot.status,
          captured_at: snapshot.captured_at,
          capture_duration_ms: snapshot.capture_duration_ms,
          screenshot_url: snapshot.screenshot_url,
          thumbnail_url: snapshot.thumbnail_url,
          width: snapshot.width,
          height: snapshot.height
        }

        if include_comparison && snapshot.comparison
          comp = snapshot.comparison
          data[:comparison] = {
            id: comp.id,
            status: comp.status,
            diff_percentage: comp.diff_percentage,
            diff_pixels: comp.diff_pixels,
            within_threshold: comp.within_threshold,
            review_status: comp.review_status,
            diff_image_url: comp.diff_image_url
          }
        end

        data
      end
    end
  end
end
