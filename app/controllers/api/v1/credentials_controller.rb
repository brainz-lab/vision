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

        # Store the actual credential in Vault
        if params[:username].present? || params[:password].present?
          begin
            credential.store!(
              username: params[:username],
              password: params[:password]
            )
          rescue VaultClient::VaultError => e
            return render json: { error: "Failed to store credential in Vault: #{e.message}" }, status: :unprocessable_entity
          end
        end

        if credential.save
          render json: { credential: credential_json(credential) }, status: :created
        else
          render json: { errors: credential.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PUT /api/v1/credentials/:id
      # Update credential metadata and optionally update Vault value
      def update
        # Update Vault if new credentials provided
        if params[:username].present? || params[:password].present?
          begin
            # Fetch existing to merge
            existing = @credential.fetch rescue {}

            @credential.store!(
              username: params[:username] || existing[:username],
              password: params[:password] || existing[:password]
            )
          rescue VaultClient::VaultError => e
            return render json: { error: "Failed to update credential in Vault: #{e.message}" }, status: :unprocessable_entity
          end
        end

        if @credential.update(credential_params)
          render json: { credential: credential_json(@credential) }
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
