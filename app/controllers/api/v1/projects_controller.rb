module Api
  module V1
    class ProjectsController < ActionController::API
      before_action :authenticate_master_key!, only: [:provision]

      # POST /api/v1/projects/provision
      # Auto-provision a project (called by SDK)
      def provision
        project = Project.find_or_create_by!(
          platform_project_id: params[:platform_project_id] || "vis_#{SecureRandom.hex(8)}"
        ) do |p|
          p.name = params[:name] || 'Vision Project'
          p.base_url = params[:base_url] || 'https://example.com'
          p.environment = params[:environment] || 'development'
          p.settings = {
            'api_key' => "vis_#{SecureRandom.hex(16)}"
          }
        end

        render json: {
          id: project.id,
          name: project.name,
          platform_project_id: project.platform_project_id,
          api_key: project.settings['api_key'],
          base_url: project.base_url
        }, status: :created
      end

      # GET /api/v1/projects/lookup
      def lookup
        project = Project.find_by!(platform_project_id: params[:platform_project_id])

        render json: {
          id: project.id,
          name: project.name,
          platform_project_id: project.platform_project_id,
          base_url: project.base_url,
          environment: project.environment
        }
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Project not found' }, status: :not_found
      end

      private

      def authenticate_master_key!
        key = request.headers['X-Master-Key']
        expected = ENV['VISION_MASTER_KEY']

        return if key.present? && expected.present? && ActiveSupport::SecurityUtils.secure_compare(key, expected)

        render json: { error: 'Unauthorized' }, status: :unauthorized
      end
    end
  end
end
