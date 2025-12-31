# frozen_string_literal: true

class CreateActionCacheEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :action_cache_entries, id: :uuid do |t|
      t.references :project, type: :uuid, null: false, foreign_key: true

      # Cache key
      t.string :url_pattern, null: false
      t.string :action_type, null: false
      t.string :instruction_hash  # Hash of the instruction for matching

      # Cached action data
      t.jsonb :action_data, null: false, default: {}
      t.jsonb :context, default: {}  # Page state when action was recorded

      # Usage statistics
      t.integer :success_count, default: 1
      t.integer :failure_count, default: 0
      t.float :avg_duration_ms

      # Lifecycle
      t.datetime :last_used_at
      t.datetime :expires_at

      t.timestamps

      t.index [ :project_id, :url_pattern, :action_type ]
      t.index [ :project_id, :instruction_hash ]
      t.index :expires_at
      t.index :last_used_at
    end
  end
end
