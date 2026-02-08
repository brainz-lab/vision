# frozen_string_literal: true

module Api
  module V1
    class ProjectsController < ActionController::API
      before_action :authenticate_master_key!, only: [:provision]

      # POST /api/v1/projects/provision
      # Creates a new project or returns existing one, linked to Platform
      def provision
        platform_project_id = params[:platform_project_id]
        name = params[:name]&.strip

        # If platform_project_id provided, use it as the primary key
        if platform_project_id.present?
          project = Project.find_or_initialize_by(platform_project_id: platform_project_id)
          project.name = name if name.present?
          project.base_url = params[:base_url] if params[:base_url].present?
          project.environment = params[:environment] if params[:environment].present?

          if project.new_record?
            project.base_url ||= "https://example.com"
            ensure_project_keys(project)
          end

          project.save!
        elsif name.present?
          # Fallback for standalone mode (no Platform integration)
          project = Project.find_or_initialize_by(name: name)

          if project.new_record?
            project.platform_project_id = "vis_#{SecureRandom.hex(8)}"
            project.base_url = params[:base_url] || "https://example.com"
            project.environment = params[:environment] || "development"
            ensure_project_keys(project)
            project.save!
          end
        else
          return render json: { error: "Either platform_project_id or name is required" }, status: :bad_request
        end

        render json: {
          id: project.id,
          platform_project_id: project.platform_project_id,
          name: project.name,
          slug: project.name.parameterize,
          environment: project.environment,
          base_url: project.base_url,
          ingest_key: project.settings&.dig("ingest_key"),
          api_key: project.settings&.dig("api_key")
        }, status: project.previously_new_record? ? :created : :ok
      end

      # GET /api/v1/projects/lookup
      # Looks up a project by name or platform_project_id
      def lookup
        project = find_project

        if project
          render json: {
            id: project.id,
            platform_project_id: project.platform_project_id,
            name: project.name,
            slug: project.name.parameterize,
            environment: project.environment,
            base_url: project.base_url
          }
        else
          render json: { error: "Project not found" }, status: :not_found
        end
      end

      private

      def find_project
        if params[:platform_project_id].present?
          Project.find_by(platform_project_id: params[:platform_project_id])
        elsif params[:name].present?
          Project.find_by(name: params[:name])
        end
      end

      def ensure_project_keys(project)
        project.settings ||= {}
        project.settings["ingest_key"] ||= "vis_ingest_#{SecureRandom.hex(16)}"
        project.settings["api_key"] ||= "vis_api_#{SecureRandom.hex(16)}"
      end

      def authenticate_master_key!
        key = request.headers["X-Master-Key"]
        expected = ENV["VISION_MASTER_KEY"]

        return if key.present? && expected.present? && ActiveSupport::SecurityUtils.secure_compare(key, expected)

        render json: { error: "Unauthorized" }, status: :unauthorized
      end
    end
  end
end
