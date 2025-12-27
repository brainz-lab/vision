class SsoController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false

  # GET /sso/callback
  # Handle SSO callback from Platform
  def callback
    token = params[:token]
    return_to = params[:return_to] || dashboard_root_path

    if token.blank?
      redirect_to safe_return_to(return_to), alert: 'SSO token missing'
      return
    end

    # Validate token with Platform
    result = validate_sso_token(token)

    if result[:valid]
      session[:user_id] = result[:user_id]
      session[:user_email] = result[:email]
      session[:project_id] = result[:project_id]

      redirect_to safe_return_to(return_to), allow_other_host: true, notice: 'Signed in successfully'
    else
      redirect_to safe_return_to(return_to), alert: 'SSO authentication failed'
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
      'brainzlab.ai',
      'vision.brainzlab.ai',
      'platform.brainzlab.ai',
      'localhost'
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
        user_id: 'dev_user',
        email: 'dev@brainzlab.ai',
        project_id: 'dev_project'
      }
    else
      # Make request to Platform to validate token
      PlatformClient.validate_sso_token(token)
    end
  end
end
