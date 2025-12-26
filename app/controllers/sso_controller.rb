class SsoController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false

  # GET /sso/callback
  # Handle SSO callback from Platform
  def callback
    token = params[:token]
    return_to = params[:return_to] || dashboard_root_path

    if token.blank?
      redirect_to return_to, alert: 'SSO token missing'
      return
    end

    # Validate token with Platform
    result = validate_sso_token(token)

    if result[:valid]
      session[:user_id] = result[:user_id]
      session[:user_email] = result[:email]
      session[:project_id] = result[:project_id]

      redirect_to return_to, notice: 'Signed in successfully'
    else
      redirect_to return_to, alert: 'SSO authentication failed'
    end
  end

  private

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
