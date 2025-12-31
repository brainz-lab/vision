# frozen_string_literal: true

class CreateCredentials < ActiveRecord::Migration[8.0]
  def change
    create_table :credentials, id: :uuid do |t|
      t.references :project, null: false, foreign_key: true, type: :uuid

      # Credential identification
      t.string :name, null: false  # e.g., "github", "aws-console", "my-service"
      t.string :service_url        # Optional URL pattern this credential is for

      # Vault reference (never store actual credentials)
      t.string :vault_path, null: false  # e.g., "/projects/xxx/credentials/github"
      t.string :vault_environment, default: "production"

      # Credential type and metadata
      t.string :credential_type, default: "login"  # login, api_key, oauth, cookie
      t.jsonb :metadata, default: {}  # Additional config (e.g., login_url, username_field)

      # Usage tracking
      t.datetime :last_used_at
      t.integer :use_count, default: 0

      # Status
      t.boolean :active, default: true
      t.datetime :expires_at

      t.timestamps
    end

    add_index :credentials, [ :project_id, :name ], unique: true
    add_index :credentials, :vault_path
    add_index :credentials, :service_url
    add_index :credentials, :active
  end
end
