# frozen_string_literal: true

class AddBrowserSessionToAiTasks < ActiveRecord::Migration[8.0]
  def change
    add_reference :ai_tasks, :browser_session, type: :uuid, foreign_key: true, index: true
  end
end
