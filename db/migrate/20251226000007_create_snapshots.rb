class CreateSnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :snapshots, id: :uuid do |t|
      t.references :page, type: :uuid, null: false, foreign_key: true
      t.references :browser_config, type: :uuid, null: false, foreign_key: true
      t.references :test_run, type: :uuid, foreign_key: true

      # Context
      t.string :branch
      t.string :commit_sha
      t.string :environment  # staging, production, pr-123
      t.string :triggered_by  # ci, manual, synapse

      # Screenshot (ActiveStorage handles the actual file)
      t.string :screenshot_key  # ActiveStorage blob key
      t.string :thumbnail_key
      t.integer :file_size
      t.integer :width
      t.integer :height

      # Capture details
      t.datetime :captured_at
      t.integer :capture_duration_ms
      t.jsonb :metadata, default: {}  # Browser version, timing, etc.

      # Status
      t.string :status, default: 'pending'  # pending, captured, comparing, compared, error

      t.timestamps

      t.index [:page_id, :captured_at]
      t.index [:test_run_id, :page_id]
      t.index [:test_run_id, :status]
    end
  end
end
