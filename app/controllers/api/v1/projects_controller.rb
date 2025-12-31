module Api
  module V1
    class ProjectsController < ActionController::API
      before_action :authenticate_master_key!, only: [ :provision ]

      # POST /api/v1/projects/provision
      # Auto-provision a project (called by SDK)
      # Follows same pattern as Recall/Reflex for consistency
      def provision
        name = params[:name]&.strip
        return render json: { error: "name is required" }, status: :unprocessable_entity if name.blank?

        project = Project.find_or_initialize_by(name: name)

        if project.new_record?
          project.platform_project_id = params[:platform_project_id] || "vis_#{SecureRandom.hex(8)}"
          project.base_url = params[:base_url] || "https://example.com"
          project.environment = params[:environment] || "development"

          # Generate keys following service pattern
          ingest_key = "vis_ingest_#{SecureRandom.hex(16)}"
          api_key = "vis_api_#{SecureRandom.hex(16)}"

          project.settings = (project.settings || {}).merge(
            "ingest_key" => ingest_key,
            "api_key" => api_key
          )

          project.save!
        end

        render json: {
          id: project.id,
          name: project.name,
          slug: project.name.parameterize,
          platform_project_id: project.platform_project_id,
          ingest_key: project.settings["ingest_key"],
          api_key: project.settings["api_key"],
          base_url: project.base_url
        }, status: :created
      end

      # GET /api/v1/projects/lookup
      def lookup
        project = if params[:platform_project_id].present?
          Project.find_by!(platform_project_id: params[:platform_project_id])
        elsif params[:name].present?
          Project.find_by!(name: params[:name])
        else
          raise ActiveRecord::RecordNotFound
        end

        render json: {
          id: project.id,
          name: project.name,
          slug: project.name.parameterize,
          platform_project_id: project.platform_project_id,
          base_url: project.base_url,
          environment: project.environment
        }
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Project not found" }, status: :not_found
      end

      private

      def authenticate_master_key!
        key = request.headers["X-Master-Key"]
        expected = ENV["VISION_MASTER_KEY"]

        return if key.present? && expected.present? && ActiveSupport::SecurityUtils.secure_compare(key, expected)

        render json: { error: "Unauthorized" }, status: :unauthorized
      end
    end
  end
end
