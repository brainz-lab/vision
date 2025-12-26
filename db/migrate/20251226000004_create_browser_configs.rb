class CreateBrowserConfigs < ActiveRecord::Migration[8.0]
  def change
    create_table :browser_configs, id: :uuid do |t|
      t.references :project, type: :uuid, null: false, foreign_key: true

      t.string :browser, null: false  # chromium, firefox, webkit
      t.string :name, null: false     # "Chrome Desktop", "Mobile Safari"

      t.integer :width, null: false
      t.integer :height, null: false
      t.float :device_scale_factor, default: 1.0
      t.boolean :is_mobile, default: false
      t.boolean :has_touch, default: false
      t.string :user_agent

      t.boolean :enabled, default: true

      t.timestamps

      t.index [:project_id, :browser]
      t.index [:project_id, :enabled]
    end
  end
end
