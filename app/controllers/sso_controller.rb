class SsoController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false

  # GET /sso/callback - Callback from Platform SSO
  def callback
    token = params[:token]

    if token.blank?
      redirect_to platform_external_url, allow_other_host: true
      return
    end

    # Validate token with Platform (internal network)
    user_info = validate_sso_token(token)

    if user_info[:valid]
      session[:platform_user_id] = user_info[:user_id]
      session[:platform_project_id] = user_info[:project_id]
      session[:platform_organization_id] = user_info[:organization_id]
      session[:project_slug] = user_info[:project_slug]
      session[:user_email] = user_info[:user_email]
      session[:user_name] = user_info[:user_name]

      # Sync all user's projects from Platform
      sync_projects_from_platform(token)

      # Ensure at least the current project exists (fallback if full sync failed)
      ensure_project_exists(user_info)

      redirect_to params[:return_to] || dashboard_root_path
    else
      redirect_to "#{platform_external_url}/login?error=sso_failed", allow_other_host: true
    end
  end

  def logout
    session.delete(:platform_user_id)
    session.delete(:platform_project_id)
    session.delete(:platform_organization_id)
    session.delete(:project_slug)
    session.delete(:user_email)
    session.delete(:user_name)

    redirect_to root_path, notice: "Logged out successfully"
  end

  private

  def validate_sso_token(token)
    if Rails.env.development?
      return {
        valid: true,
        user_id: "dev_user",
        user_email: "dev@brainzlab.ai",
        user_name: "Dev User",
        project_id: "dev_project",
        project_slug: "dev-project",
        organization_id: nil
      }
    end

    uri = URI("#{platform_internal_url}/api/v1/sso/validate")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"

    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "application/json"
    request["X-Service-Key"] = ENV["SERVICE_KEY"]
    request.body = { token: token, product: "vision" }.to_json

    response = http.request(request)

    if response.code == "200"
      JSON.parse(response.body, symbolize_names: true).merge(valid: true)
    else
      Rails.logger.error("[SSO] Token validation failed: #{response.code} #{response.body}")
      { valid: false }
    end
  rescue => e
    Rails.logger.error("[SSO] Token validation failed: #{e.message}")
    { valid: false }
  end

  def sync_projects_from_platform(sso_token)
    projects_data = fetch_user_projects(sso_token)
    return unless projects_data

    platform_ids = projects_data.map { |d| d["id"].to_s }

    projects_data.each do |data|
      project = Project.find_or_initialize_by(platform_project_id: data["id"].to_s)
      project.name = data["name"]
      project.base_url ||= "https://example.com"
      project.environment = data["environment"] || "live"
      project.archived_at = nil
      project.save!
    end

    Project.where.not(platform_project_id: [nil, ""])
           .where.not(platform_project_id: platform_ids)
           .where(archived_at: nil)
           .update_all(archived_at: Time.current)

    Rails.logger.info("[SSO] Synced #{projects_data.count} projects from Platform")
  rescue => e
    Rails.logger.error("[SSO] Project sync failed: #{e.message}")
  end

  # Fallback: ensure at least the current project exists from SSO validation data
  def ensure_project_exists(user_info)
    return unless user_info[:project_id].present?

    project = Project.find_or_initialize_by(platform_project_id: user_info[:project_id].to_s)
    return if project.persisted?

    project.name = user_info[:project_slug] || "Project #{user_info[:project_id]}"
    project.base_url = "https://example.com"
    project.environment = "live"
    project.save!
    Rails.logger.info("[SSO] Created project from SSO validation: #{project.name}")
  rescue => e
    Rails.logger.error("[SSO] ensure_project_exists failed: #{e.message}")
  end

  def fetch_user_projects(sso_token)
    uri = URI("#{platform_internal_url}/api/v1/user/projects")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 10

    request = Net::HTTP::Get.new(uri.path)
    request["Accept"] = "application/json"
    request["X-SSO-Token"] = sso_token

    response = http.request(request)

    if response.code == "200"
      JSON.parse(response.body)["projects"]
    else
      nil
    end
  rescue => e
    Rails.logger.error("[SSO] fetch_user_projects failed: #{e.message}")
    nil
  end

  # Internal URL for service-to-service API calls (K8s network)
  def platform_internal_url
    ENV["BRAINZLAB_PLATFORM_URL"] || "http://platform:3000"
  end

  # External URL for browser redirects
  def platform_external_url
    ENV["BRAINZLAB_PLATFORM_EXTERNAL_URL"] || "http://platform.localhost"
  end
end
