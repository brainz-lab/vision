class CreateComparisons < ActiveRecord::Migration[8.0]
  def change
    create_table :comparisons, id: :uuid do |t|
      t.references :baseline, type: :uuid, null: false, foreign_key: true
      t.references :snapshot, type: :uuid, null: false, foreign_key: true
      t.references :test_run, type: :uuid, foreign_key: true

      # Diff result
      t.string :status, null: false  # passed, failed, pending, error
      t.float :diff_percentage  # 0.0 - 100.0
      t.integer :diff_pixels  # Number of different pixels
      t.string :diff_image_key  # ActiveStorage blob key for diff image

      # Thresholds
      t.float :threshold_used  # 0.01 = 1%
      t.boolean :within_threshold

      # Review
      t.string :review_status  # pending, approved, rejected
      t.datetime :reviewed_at
      t.string :reviewed_by
      t.text :review_notes

      # Performance
      t.integer :comparison_duration_ms

      t.timestamps

      t.index [ :test_run_id, :status ]
      t.index [ :review_status ]
    end
  end
end
