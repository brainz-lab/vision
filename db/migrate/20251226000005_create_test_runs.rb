class CreateTestRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :test_runs, id: :uuid do |t|
      t.references :project, type: :uuid, null: false, foreign_key: true

      # Context
      t.string :branch
      t.string :commit_sha
      t.string :commit_message
      t.string :environment
      t.string :triggered_by  # ci, manual, synapse, webhook
      t.string :trigger_source  # github, gitlab, api

      # PR info
      t.string :pr_number
      t.string :pr_url
      t.string :base_branch  # What to compare against

      # Status
      t.string :status, default: 'pending'  # pending, running, passed, failed, error
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_ms

      # Results
      t.integer :total_pages, default: 0
      t.integer :passed_count, default: 0
      t.integer :failed_count, default: 0
      t.integer :pending_count, default: 0
      t.integer :error_count, default: 0

      # Notifications
      t.boolean :notified, default: false
      t.jsonb :notification_channels, default: []

      t.timestamps

      t.index [:project_id, :created_at]
      t.index [:project_id, :branch]
      t.index [:project_id, :pr_number]
      t.index [:project_id, :status]
    end
  end
end
