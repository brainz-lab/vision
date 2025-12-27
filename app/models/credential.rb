# frozen_string_literal: true

# Credential represents a reference to a secret stored in Vault
# Vision NEVER stores actual credential values - only Vault paths
#
# Usage:
#   credential = project.credentials.find_by(name: "github")
#   creds = credential.fetch  # => { username: "...", password: "..." }
#
class Credential < ApplicationRecord
  belongs_to :project

  # Credential types
  TYPES = %w[login api_key oauth cookie bearer].freeze

  validates :name, presence: true,
                   uniqueness: { scope: :project_id },
                   format: { with: /\A[a-z0-9_-]+\z/i, message: "must be alphanumeric with dashes/underscores" }
  validates :vault_path, presence: true
  validates :credential_type, inclusion: { in: TYPES }

  scope :active, -> { where(active: true).where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :for_url, ->(url) { where("service_url IS NULL OR ? LIKE REPLACE(service_url, '*', '%')", url) }
  scope :login_credentials, -> { where(credential_type: "login") }

  before_validation :set_vault_path, on: :create

  # Fetch the actual credential values from Vault
  # @return [Hash] Credential data (varies by type)
  # @raise [VaultClient::VaultError] If fetch fails
  def fetch
    vault_client.get_credential(name, project_id: project.platform_project_id, environment: vault_environment)
  rescue VaultClient::NotFoundError
    # Try direct path fetch as fallback
    secret = vault_client.get_secret(vault_path, environment: vault_environment)
    parse_credential_value(secret[:value])
  ensure
    record_usage!
  end

  # Check if credential is expired
  def expired?
    expires_at.present? && expires_at < Time.current
  end

  # Check if credential matches a given URL
  def matches_url?(url)
    return true if service_url.blank?

    pattern = service_url.gsub("*", ".*")
    url.match?(Regexp.new(pattern, Regexp::IGNORECASE))
  end

  # Get login field selectors (for browser automation)
  def login_selectors
    {
      username_field: metadata["username_field"] || 'input[type="text"], input[type="email"], input[name*="user"], input[name*="email"]',
      password_field: metadata["password_field"] || 'input[type="password"]',
      submit_button: metadata["submit_button"] || 'button[type="submit"], input[type="submit"], button:has-text("Login"), button:has-text("Sign in")',
      login_url: metadata["login_url"] || service_url
    }
  end

  # Store credential in Vault (convenience method)
  # @param username [String]
  # @param password [String]
  def store!(username:, password:)
    vault_client.set_credential(
      name,
      username: username,
      password: password,
      project_id: project.platform_project_id,
      environment: vault_environment,
      metadata: {
        service_url: service_url,
        credential_type: credential_type
      }
    )
  end

  private

  def set_vault_path
    return if vault_path.present?

    self.vault_path = "/projects/#{project.platform_project_id}/credentials/#{name}"
  end

  def vault_client
    @vault_client ||= VaultClient.for_project(project)
  end

  def record_usage!
    update_columns(
      last_used_at: Time.current,
      use_count: use_count + 1
    )
  end

  def parse_credential_value(value)
    # Try parsing as JSON first
    JSON.parse(value, symbolize_names: true)
  rescue JSON::ParserError
    # Treat as password-only
    { password: value }
  end
end
