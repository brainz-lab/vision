# frozen_string_literal: true

class CreateAiTasks < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_tasks, id: :uuid do |t|
      t.references :project, type: :uuid, null: false, foreign_key: true

      # Task definition
      t.text :instruction, null: false
      t.string :start_url
      t.string :final_url

      # Configuration
      t.string :model, null: false, default: "claude-sonnet-4"
      t.string :browser_provider, null: false, default: "local"
      t.integer :max_steps, default: 25
      t.integer :timeout_seconds, default: 300
      t.boolean :capture_screenshots, default: true
      t.jsonb :viewport, default: { width: 1280, height: 720 }

      # Status tracking
      t.string :status, null: false, default: "pending"
      t.integer :steps_executed, default: 0
      t.text :result
      t.jsonb :extracted_data, default: {}
      t.text :error_message
      t.boolean :stop_requested, default: false

      # Metadata
      t.string :triggered_by  # api, mcp, webhook, scheduled, synapse
      t.jsonb :metadata, default: {}

      # Timing
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_ms

      t.timestamps

      t.index [ :project_id, :status ]
      t.index [ :project_id, :created_at ]
      t.index :status
      t.index :triggered_by
    end
  end
end
