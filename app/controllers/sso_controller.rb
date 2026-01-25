class SsoController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false

  # GET /sso/callback
  # Handle SSO callback from Platform
  def callback
    token = params[:token]
    return_to = params[:return_to] || dashboard_root_path

    if token.blank?
      redirect_to safe_return_to(return_to), alert: "SSO token missing"
      return
    end

    # Validate token with Platform
    result = validate_sso_token(token)

    if result[:valid]
      session[:user_id] = result[:user_id]
      session[:user_email] = result[:email]
      session[:project_id] = result[:project_id]

      # Sync all user's projects from Platform
      sync_projects_from_platform(token)

      redirect_to safe_return_to(return_to), allow_other_host: true, notice: "Signed in successfully"
    else
      redirect_to safe_return_to(return_to), alert: "SSO authentication failed"
    end
  end

  private

  # Validate return_to URL to prevent open redirect attacks
  # Only allow redirects to trusted hosts or internal paths
  def safe_return_to(url)
    return dashboard_root_path if url.blank?

    uri = URI.parse(url)

    # Allow relative paths
    return url if uri.host.nil?

    # Allow trusted hosts
    trusted_hosts = [
      "brainzlab.ai",
      "vision.brainzlab.ai",
      "platform.brainzlab.ai",
      "localhost"
    ]

    if trusted_hosts.any? { |host| uri.host == host || uri.host&.end_with?(".#{host}") }
      url
    else
      dashboard_root_path
    end
  rescue URI::InvalidURIError
    dashboard_root_path
  end

  def validate_sso_token(token)
    # In production, validate with Platform
    # For development, accept any token
    if Rails.env.development?
      {
        valid: true,
        user_id: "dev_user",
        email: "dev@brainzlab.ai",
        project_id: "dev_project"
      }
    else
      # Make request to Platform to validate token
      PlatformClient.validate_sso_token(token)
    end
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

  def fetch_user_projects(sso_token)
    platform_url = ENV["BRAINZLAB_PLATFORM_URL"] || "http://platform:3000"
    uri = URI("#{platform_url}/api/v1/user/projects")
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
end
