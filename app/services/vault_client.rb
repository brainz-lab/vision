# frozen_string_literal: true

# Client for communicating with Vault service to fetch credentials securely
# Vision never stores credential values - only references to Vault paths
#
# Example:
#   client = VaultClient.for_project(project)
#   creds = client.get_credential("my-service", project_id: project.platform_project_id)
#   # => { username: "user@example.com", password: "secret" }
#
class VaultClient
  class VaultError < StandardError; end
  class AuthenticationError < VaultError; end
  class NotFoundError < VaultError; end
  class AccessDeniedError < VaultError; end

  VAULT_URL = ENV.fetch("BRAINZLAB_VAULT_URL", "http://localhost:4009")
  REQUEST_TIMEOUT = 30

  attr_reader :access_token

  def initialize(access_token:)
    @access_token = access_token
  end

  # Fetch a secret value from Vault
  # @param key [String] Secret key (e.g., "GITHUB_CRED")
  # @param environment [String] Environment (production, staging, development)
  # @return [Hash] Secret data with :value and metadata
  def get_secret(key, environment: "production")
    vault_key = normalize_key(key)

    response = request(:get, "/api/v1/secrets/#{vault_key}", {
      environment: environment
    })

    {
      value: response[:value],
      version: response[:version],
      updated_at: response[:updated_at]
    }
  rescue Faraday::ResourceNotFound
    raise NotFoundError, "Secret not found: #{key}"
  rescue Faraday::UnauthorizedError
    raise AuthenticationError, "Invalid Vault access token"
  rescue Faraday::ForbiddenError
    raise AccessDeniedError, "Access denied to secret: #{key}"
  end

  # Get multiple secrets by paths (batch fetch)
  # @param paths [Array<String>] Secret paths
  # @param environment [String] Environment
  # @return [Hash] Map of path => value
  def get_secrets(paths, environment: "production")
    response = request(:post, "/api/v1/secrets/batch", {
      paths: paths,
      environment: environment
    })

    response[:secrets].transform_keys(&:to_s)
  end

  # Store a new secret in Vault
  # @param key [String] Secret key (will be uppercased with underscores)
  # @param value [String] Secret value
  # @param environment [String] Environment
  # @param metadata [Hash] Optional metadata
  def set_secret(key, value, environment: "production", metadata: {})
    # Convert key to Vault-compatible format (uppercase with underscores)
    vault_key = normalize_key(key)

    request(:post, "/api/v1/secrets", {
      key: vault_key,
      value: value,
      environment: environment,
      metadata: metadata
    })
  end

  # List available secrets (paths only, not values)
  # @param prefix [String] Optional path prefix filter
  # @return [Array<Hash>] List of secret metadata
  def list_secrets(prefix: nil)
    params = prefix ? { prefix: prefix } : {}
    response = request(:get, "/api/v1/secrets", params)
    response[:secrets]
  end

  # Get credential by name (convenience method for browser automation)
  # @param name [String] Credential name (e.g., "github", "aws-console")
  # @param project_id [String] Project ID for scoping
  # @param environment [String] Environment
  # @return [Hash] Credential with :username and :password
  def get_credential(name, project_id:, environment: "production")
    key = credential_key(name, project_id)
    secret = get_secret(key, environment: environment)

    # Credentials are stored as JSON with username/password
    JSON.parse(secret[:value], symbolize_names: true)
  rescue JSON::ParserError
    # Fallback: treat as password-only credential
    { password: secret[:value] }
  end

  # Store a credential for browser automation
  # @param name [String] Credential name
  # @param username [String] Username
  # @param password [String] Password
  # @param project_id [String] Project ID
  # @param environment [String] Environment
  # @param metadata [Hash] Additional metadata (e.g., :url, :notes)
  def set_credential(name, username:, password:, project_id:, environment: "production", metadata: {})
    key = credential_key(name, project_id)
    value = { username: username, password: password }.to_json

    set_secret(key, value, environment: environment, metadata: metadata.merge(
      type: "credential",
      service: name,
      project_id: project_id
    ))
  end

  # Health check for Vault service
  def healthy?
    response = connection.get("/health")
    response.status == 200
  rescue Faraday::Error
    false
  end

  private

  def request(method, path, params = {})
    response = case method
    when :get
      connection.get(path, params)
    when :post
      connection.post(path, params.to_json)
    when :put
      connection.put(path, params.to_json)
    when :delete
      connection.delete(path, params)
    end

    JSON.parse(response.body, symbolize_names: true)
  rescue Faraday::Error => e
    raise VaultError, "Vault request failed: #{e.message}"
  end

  def connection
    @connection ||= Faraday.new(url: VAULT_URL) do |f|
      f.request :json
      f.response :raise_error
      f.adapter Faraday.default_adapter
      f.headers["Authorization"] = "Bearer #{access_token}"
      f.headers["Content-Type"] = "application/json"
      f.options.timeout = REQUEST_TIMEOUT
      f.options.open_timeout = 5
    end
  end

  def encode_path(path)
    # Remove leading slash and encode for URL
    path.gsub(%r{^/}, "").split("/").map { |p| ERB::Util.url_encode(p) }.join("/")
  end

  # Normalize a key to Vault-compatible format (uppercase with underscores)
  # Examples:
  #   "github" -> "GITHUB"
  #   "my-service" -> "MY_SERVICE"
  #   "aws.console" -> "AWS_CONSOLE"
  def normalize_key(key)
    key.to_s
       .gsub(/[^a-zA-Z0-9]/, "_")  # Replace non-alphanumeric with underscore
       .gsub(/_+/, "_")            # Collapse multiple underscores
       .gsub(/^_|_$/, "")          # Remove leading/trailing underscores
       .upcase                      # Uppercase
       .tap { |k| k.prepend("C") if k.match?(/^\d/) }  # Prefix with C if starts with digit
  end

  # Generate a credential key from name and project ID
  # Creates a unique, Vault-compatible key for credentials
  def credential_key(name, project_id)
    # Use a shortened project ID for readability
    short_id = project_id.to_s.gsub("-", "")[0..7].upcase
    "CRED_#{short_id}_#{normalize_key(name)}"
  end

  class << self
    # Create a client for a Vision project
    # Uses the project's Vault access token
    def for_project(project)
      token = project.vault_access_token
      raise AuthenticationError, "Project has no Vault access token configured" unless token.present?

      new(access_token: token)
    end

    # Create a client with a service token (for system operations)
    def service_client
      token = ENV.fetch("VAULT_SERVICE_TOKEN") { raise AuthenticationError, "VAULT_SERVICE_TOKEN not configured" }
      new(access_token: token)
    end
  end
end
