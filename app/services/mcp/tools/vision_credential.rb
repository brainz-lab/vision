# frozen_string_literal: true

module Mcp
  module Tools
    # Store and manage credentials for browser automation
    # Credentials are securely stored in Vault - Vision only keeps references
    class VisionCredential < Base
      DESCRIPTION = "Store, list, or manage credentials for authenticated browser tasks. Credentials are securely stored in Vault with encryption at rest. Use this to save login credentials that can be used with vision_task's credential parameter."

      SCHEMA = {
        type: "object",
        properties: {
          action: {
            type: "string",
            enum: %w[store list delete test],
            description: "Action to perform: 'store' saves new credentials, 'list' shows all credentials, 'delete' removes a credential, 'test' verifies a credential works"
          },
          name: {
            type: "string",
            description: "Unique name for the credential (e.g., 'github', 'aws-console'). Required for store, delete, and test actions."
          },
          username: {
            type: "string",
            description: "Username or email for login. Required for store action."
          },
          password: {
            type: "string",
            description: "Password for login. Required for store action. This is securely encrypted in Vault."
          },
          service_url: {
            type: "string",
            description: "Optional URL pattern for the service (e.g., 'https://github.com/*'). Helps with auto-detection."
          },
          login_url: {
            type: "string",
            description: "Optional specific login page URL. Used for auto_login feature."
          },
          credential_type: {
            type: "string",
            enum: %w[login api_key bearer cookie],
            default: "login",
            description: "Type of credential. Most web logins use 'login'."
          },
          environment: {
            type: "string",
            enum: %w[production staging development],
            default: "production",
            description: "Vault environment to store in"
          }
        },
        required: %w[action]
      }.freeze

      def call(args)
        action = args[:action]

        case action
        when "store"
          store_credential(args)
        when "list"
          list_credentials
        when "delete"
          delete_credential(args[:name])
        when "test"
          test_credential(args[:name])
        else
          error("Unknown action: #{action}")
        end
      rescue VaultClient::VaultError => e
        error("Vault error: #{e.message}")
      rescue => e
        error("Failed: #{e.message}")
      end

      private

      def store_credential(args)
        name = args[:name]
        username = args[:username]
        password = args[:password]

        return error("Name is required") if name.blank?
        return error("Username is required") if username.blank?
        return error("Password is required") if password.blank?

        # Check if credential already exists
        existing = project.credentials.find_by(name: name)

        if existing
          # Update existing credential
          existing.store!(username: username, password: password)
          existing.update!(
            service_url: args[:service_url],
            credential_type: args[:credential_type] || "login",
            vault_environment: args[:environment] || "production",
            metadata: existing.metadata.merge(
              "login_url" => args[:login_url]
            ).compact
          )

          success({
            message: "Credential '#{name}' updated successfully",
            credential: credential_info(existing)
          })
        else
          # Create new credential
          credential = project.credentials.create!(
            name: name,
            service_url: args[:service_url],
            credential_type: args[:credential_type] || "login",
            vault_environment: args[:environment] || "production",
            metadata: { "login_url" => args[:login_url] }.compact
          )

          credential.store!(username: username, password: password)

          success({
            message: "Credential '#{name}' stored successfully",
            credential: credential_info(credential),
            usage: "Use this credential with: vision_task(instruction: '...', credential: '#{name}')"
          })
        end
      end

      def list_credentials
        credentials = project.credentials.active

        success({
          credentials: credentials.map { |c| credential_info(c) },
          total: credentials.count
        })
      end

      def delete_credential(name)
        return error("Name is required") if name.blank?

        credential = project.credentials.find_by(name: name)
        return error("Credential '#{name}' not found") unless credential

        credential.update!(active: false)

        success({
          message: "Credential '#{name}' deleted",
          note: "Credential history is preserved in Vault for audit purposes"
        })
      end

      def test_credential(name)
        return error("Name is required") if name.blank?

        credential = project.credentials.find_by(name: name)
        return error("Credential '#{name}' not found") unless credential

        begin
          creds = credential.fetch

          success({
            name: name,
            valid: true,
            has_username: creds[:username].present?,
            has_password: creds[:password].present?,
            last_used_at: credential.last_used_at,
            use_count: credential.use_count
          })
        rescue VaultClient::VaultError => e
          success({
            name: name,
            valid: false,
            error: e.message
          })
        end
      end

      def credential_info(credential)
        {
          name: credential.name,
          service_url: credential.service_url,
          credential_type: credential.credential_type,
          environment: credential.vault_environment,
          active: credential.active,
          last_used_at: credential.last_used_at,
          use_count: credential.use_count,
          created_at: credential.created_at
        }
      end
    end
  end
end
