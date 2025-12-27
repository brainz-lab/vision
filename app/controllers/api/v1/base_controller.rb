module Api
  module V1
    class BaseController < ActionController::API
      before_action :authenticate!
      before_action :check_feature_access!

      attr_reader :current_project, :key_info

      private

      def authenticate!
        raw_key = extract_api_key

        # Check if it's a Vision key (vis_ingest_*, vis_api_*, or legacy vis_*)
        if raw_key&.start_with?("vis_")
          @current_project = find_project_by_vision_key(raw_key)
          unless @current_project
            render json: { error: "Invalid API key" }, status: :unauthorized
            return
          end
          @key_info = {
            valid: true,
            project_id: @current_project.platform_project_id,
            project_name: @current_project.name,
            environment: @current_project.environment,
            features: { vision: true }
          }
          return
        end

        # Otherwise validate with Platform
        @key_info = PlatformClient.validate_key(raw_key)

        unless @key_info[:valid]
          render json: { error: "Invalid API key" }, status: :unauthorized
          return
        end

        @current_project = Project.find_or_create_for_platform!(
          platform_project_id: @key_info[:project_id],
          name: @key_info[:project_name],
          environment: @key_info[:environment]
        )
      end

      # Find project by any Vision key type
      def find_project_by_vision_key(key)
        # Try ingest_key first (SDK pattern)
        project = Project.find_by("settings->>'ingest_key' = ?", key)
        return project if project

        # Try api_key (dashboard/query pattern)
        project = Project.find_by("settings->>'api_key' = ?", key)
        return project if project

        # Legacy: try old api_key format (for backwards compatibility)
        Project.find_by("settings->>'api_key' = ?", key)
      end

      def check_feature_access!
        unless @key_info.dig(:features, :vision)
          render json: {
            error: 'Vision is not included in your plan',
            upgrade_url: 'https://brainzlab.ai/pricing'
          }, status: :forbidden
        end
      end

      def extract_api_key
        auth_header = request.headers['Authorization']
        return auth_header.sub(/^Bearer\s+/, '') if auth_header&.start_with?('Bearer ')
        request.headers['X-API-Key'] || params[:api_key]
      end

      def track_usage!(count = 1)
        PlatformClient.track_usage(
          project_id: @key_info[:project_id],
          product: 'vision',
          metric: 'snapshots',
          count: count
        )
      end
    end
  end
end
