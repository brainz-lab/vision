class CreateBaselines < ActiveRecord::Migration[8.0]
  def change
    create_table :baselines, id: :uuid do |t|
      t.references :page, type: :uuid, null: false, foreign_key: true
      t.references :browser_config, type: :uuid, null: false, foreign_key: true

      # Baseline info
      t.string :branch, default: 'main'
      t.string :commit_sha
      t.string :environment, default: 'production'

      # Screenshot (ActiveStorage handles the actual file)
      t.string :screenshot_key  # ActiveStorage blob key
      t.string :thumbnail_key
      t.integer :file_size
      t.integer :width
      t.integer :height

      # Status
      t.boolean :active, default: true  # Current baseline
      t.datetime :approved_at
      t.string :approved_by

      t.timestamps

      t.index [:page_id, :browser_config_id, :branch, :active], name: 'idx_baselines_lookup'
      t.index [:page_id, :active]
    end
  end
end
