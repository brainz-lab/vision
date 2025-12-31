# frozen_string_literal: true

class CreateTaskSteps < ActiveRecord::Migration[8.0]
  def change
    create_table :task_steps, id: :uuid do |t|
      t.references :ai_task, type: :uuid, null: false, foreign_key: true

      # Step definition
      t.integer :position, null: false
      t.string :action, null: false  # click, type, fill, navigate, scroll, hover, select, wait, extract, done
      t.string :selector
      t.text :value
      t.jsonb :action_data, default: {}

      # Result
      t.boolean :success, default: true
      t.text :error_message
      t.integer :duration_ms

      # Context
      t.string :url_before
      t.string :url_after
      t.text :reasoning  # LLM's reasoning for this action

      t.datetime :executed_at

      t.timestamps

      t.index [ :ai_task_id, :position ]
      t.index [ :ai_task_id, :success ]
    end
  end
end
