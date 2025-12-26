class CreatePages < ActiveRecord::Migration[8.0]
  def change
    create_table :pages, id: :uuid do |t|
      t.references :project, type: :uuid, null: false, foreign_key: true

      t.string :name, null: false
      t.string :path, null: false
      t.string :slug, null: false

      # Page-specific settings (override project defaults)
      t.jsonb :viewport  # { width: 1920, height: 1080 }
      t.jsonb :wait_for  # { selector: ".loaded" }
      t.integer :wait_ms  # Wait before screenshot

      # Actions before screenshot
      # [
      #   { type: "click", selector: ".accept-cookies" },
      #   { type: "scroll", y: 500 },
      #   { type: "wait", ms: 1000 }
      # ]
      t.jsonb :actions, default: []

      # Selectors to hide/mask
      t.string :hide_selectors, array: true, default: []
      t.string :mask_selectors, array: true, default: []

      t.boolean :enabled, default: true
      t.integer :position, default: 0

      t.timestamps

      t.index [:project_id, :slug], unique: true
      t.index [:project_id, :path]
      t.index [:project_id, :enabled]
    end
  end
end
