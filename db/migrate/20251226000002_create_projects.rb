class CreateProjects < ActiveRecord::Migration[8.0]
  def change
    create_table :projects, id: :uuid do |t|
      t.string :platform_project_id, null: false
      t.string :name, null: false
      t.string :base_url, null: false
      t.string :staging_url
      t.string :environment, default: 'production'

      # Settings stored as JSONB
      # {
      #   default_viewport: { width: 1280, height: 720 },
      #   browsers: ["chromium", "firefox", "webkit"],
      #   threshold: 0.01,  # 1% difference allowed
      #   wait_before_capture: 500,  # ms
      #   hide_selectors: [".ads", ".timestamp"],
      #   mask_selectors: [".dynamic-content"]
      # }
      t.jsonb :settings, default: {}

      # Auth for protected pages
      # {
      #   type: "cookie" | "basic" | "bearer",
      #   credentials: { encrypted }
      # }
      t.jsonb :auth_config, default: {}

      # Apdex threshold for test runs
      t.float :apdex_t, default: 0.5

      t.timestamps

      t.index :platform_project_id, unique: true
    end
  end
end
