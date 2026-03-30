class CreateMediaAnalyses < ActiveRecord::Migration[8.0]
  def change
    create_table :media_analyses, id: :uuid do |t|
      t.references :project, null: false, foreign_key: true, type: :uuid
      t.string :analysis_type, null: false
      t.string :status, null: false, default: "pending"
      t.string :source_url, null: false
      t.jsonb :parameters, default: {}
      t.jsonb :result, default: {}
      t.text :error_message
      t.integer :duration_ms
      t.timestamps
    end

    add_index :media_analyses, :status
    add_index :media_analyses, :analysis_type
    add_index :media_analyses, [:project_id, :status]
  end
end
