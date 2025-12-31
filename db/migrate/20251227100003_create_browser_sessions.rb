# frozen_string_literal: true

class CreateBrowserSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :browser_sessions, id: :uuid do |t|
      t.references :project, type: :uuid, null: false, foreign_key: true

      # Provider session info
      t.string :provider_session_id, null: false
      t.string :browser_provider, null: false, default: "local"
      t.string :status, null: false, default: "initializing"

      # Current state
      t.string :start_url
      t.string :current_url
      t.string :current_title
      t.jsonb :viewport, default: { width: 1280, height: 720 }

      # Provider-specific metadata
      t.jsonb :metadata, default: {}
      t.string :websocket_url
      t.string :connect_url

      # Lifecycle
      t.datetime :expires_at
      t.datetime :closed_at

      t.timestamps

      t.index [ :project_id, :status ]
      t.index :provider_session_id, unique: true
      t.index :status
      t.index :expires_at
    end
  end
end
