class CreateTestCases < ActiveRecord::Migration[8.0]
  def change
    create_table :test_cases, id: :uuid do |t|
      t.references :project, type: :uuid, null: false, foreign_key: true

      t.string :name, null: false  # "User can checkout"
      t.text :description

      # Test steps
      # [
      #   { action: "navigate", url: "/products" },
      #   { action: "click", selector: ".add-to-cart" },
      #   { action: "screenshot", name: "cart-added" },
      #   { action: "navigate", url: "/cart" },
      #   { action: "screenshot", name: "cart-page" },
      #   { action: "click", selector: "#checkout" },
      #   { action: "screenshot", name: "checkout" }
      # ]
      t.jsonb :steps, default: []

      t.string :tags, array: true, default: []
      t.boolean :enabled, default: true
      t.integer :position, default: 0

      t.timestamps

      t.index [:project_id, :enabled]
      t.index [:project_id, :name]
    end
  end
end
