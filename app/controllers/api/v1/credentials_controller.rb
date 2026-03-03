# frozen_string_literal: true

module Api
  module V1
    class CredentialsController < BaseController
      before_action :set_credential, only: [ :show, :update, :destroy, :test ]

      # GET /api/v1/credentials
      # List all credentials for the project (never returns actual values)
      def index
        credentials = @current_project.credentials.active

        render json: {
          credentials: credentials.map { |c| credential_json(c) }
        }
      end

      # GET /api/v1/credentials/:id
      # Get credential metadata (never returns actual values)
      def show
        render json: { credential: credential_json(@credential) }
      end

      # POST /api/v1/credentials
      # Create a new credential reference and store value in Vault
      def create
        credential = @current_project.credentials.new(credential_params)

        vault_warning = nil

        # Store the actual credential in Vault (if values provided)
        if params[:username].present? || params[:password].present?
          if @current_project.vault_configured?
            begin
              credential.store!(
                username: params[:username],
                password: params[:password]
              )
            rescue VaultClient::VaultError => e
              vault_warning = "Credential record saved but values could not be stored in Vault: #{e.message}"
            end
          else
            vault_warning = "Credential record saved without storing values. Vault is not configured. Set VAULT_ACCESS_TOKEN environment variable or configure via project settings."
          end
        end

        if credential.save
          response = { credential: credential_json(credential) }
          response[:warning] = vault_warning if vault_warning
          render json: response, status: :created
        else
          render json: { errors: credential.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PUT /api/v1/credentials/:id
      # Update credential metadata and optionally update Vault value
      def update
        vault_warning = nil

        # Update Vault if new credentials provided
        if params[:username].present? || params[:password].present?
          if @credential.project.vault_configured?
            begin
              existing = @credential.fetch rescue {}

              @credential.store!(
                username: params[:username] || existing[:username],
                password: params[:password] || existing[:password]
              )
            rescue VaultClient::VaultError => e
              vault_warning = "Credential metadata updated but values could not be stored in Vault: #{e.message}"
            end
          else
            vault_warning = "Credential metadata updated without storing values. Vault is not configured. Set VAULT_ACCESS_TOKEN environment variable or configure via project settings."
          end
        end

        if @credential.update(credential_params)
          response = { credential: credential_json(@credential) }
          response[:warning] = vault_warning if vault_warning
          render json: response
        else
          render json: { errors: @credential.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/credentials/:id
      # Deactivate credential (doesn't delete from Vault for audit trail)
      def destroy
        @credential.update!(active: false)
        render json: { message: "Credential deactivated" }
      end

      # POST /api/v1/credentials/:id/test
      # Test credential by attempting to fetch from Vault
      def test
        unless @credential.project.vault_configured?
          return render json: {
            success: false,
            error: "Vault is not configured. Set VAULT_ACCESS_TOKEN environment variable or configure via project settings."
          }, status: :unprocessable_entity
        end

        begin
          creds = @credential.fetch

          render json: {
            success: true,
            has_username: creds[:username].present?,
            has_password: creds[:password].present?,
            last_used_at: @credential.last_used_at,
            use_count: @credential.use_count
          }
        rescue VaultClient::VaultError => e
          render json: {
            success: false,
            error: e.message
          }, status: :unprocessable_entity
        end
      end

      private

      def set_credential
        @credential = @current_project.credentials.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Credential not found" }, status: :not_found
      end

      def credential_params
        params.permit(
          :name,
          :service_url,
          :credential_type,
          :vault_environment,
          :expires_at,
          metadata: {}
        )
      end

      def credential_json(credential)
        {
          id: credential.id,
          name: credential.name,
          service_url: credential.service_url,
          credential_type: credential.credential_type,
          vault_path: credential.vault_path,
          vault_environment: credential.vault_environment,
          vault_configured: credential.project.vault_configured?,
          active: credential.active,
          expires_at: credential.expires_at,
          last_used_at: credential.last_used_at,
          use_count: credential.use_count,
          metadata: credential.metadata,
          created_at: credential.created_at,
          updated_at: credential.updated_at
        }
      end
    end
  end
end
