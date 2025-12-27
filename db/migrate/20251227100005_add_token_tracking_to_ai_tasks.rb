# frozen_string_literal: true

class AddTokenTrackingToAiTasks < ActiveRecord::Migration[8.0]
  def change
    # Add token tracking to task_steps (per-step usage)
    add_column :task_steps, :input_tokens, :integer, default: 0
    add_column :task_steps, :output_tokens, :integer, default: 0

    # Add token tracking to ai_tasks (totals)
    add_column :ai_tasks, :total_input_tokens, :integer, default: 0
    add_column :ai_tasks, :total_output_tokens, :integer, default: 0
  end
end
