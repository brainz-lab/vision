# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2025_12_26_000010) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"
  enable_extension "timescaledb"

  create_table "active_storage_attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.uuid "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "baselines", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "active", default: true
    t.datetime "approved_at"
    t.string "approved_by"
    t.string "branch", default: "main"
    t.uuid "browser_config_id", null: false
    t.string "commit_sha"
    t.datetime "created_at", null: false
    t.string "environment", default: "production"
    t.integer "file_size"
    t.integer "height"
    t.uuid "page_id", null: false
    t.string "screenshot_key"
    t.string "thumbnail_key"
    t.datetime "updated_at", null: false
    t.integer "width"
    t.index ["browser_config_id"], name: "index_baselines_on_browser_config_id"
    t.index ["page_id", "active"], name: "index_baselines_on_page_id_and_active"
    t.index ["page_id", "browser_config_id", "branch", "active"], name: "idx_baselines_lookup"
    t.index ["page_id"], name: "index_baselines_on_page_id"
  end

  create_table "browser_configs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "browser", null: false
    t.datetime "created_at", null: false
    t.float "device_scale_factor", default: 1.0
    t.boolean "enabled", default: true
    t.boolean "has_touch", default: false
    t.integer "height", null: false
    t.boolean "is_mobile", default: false
    t.string "name", null: false
    t.uuid "project_id", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "width", null: false
    t.index ["project_id", "browser"], name: "index_browser_configs_on_project_id_and_browser"
    t.index ["project_id", "enabled"], name: "index_browser_configs_on_project_id_and_enabled"
    t.index ["project_id"], name: "index_browser_configs_on_project_id"
  end

  create_table "comparisons", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "baseline_id", null: false
    t.integer "comparison_duration_ms"
    t.datetime "created_at", null: false
    t.string "diff_image_key"
    t.float "diff_percentage"
    t.integer "diff_pixels"
    t.text "review_notes"
    t.string "review_status"
    t.datetime "reviewed_at"
    t.string "reviewed_by"
    t.uuid "snapshot_id", null: false
    t.string "status", null: false
    t.uuid "test_run_id"
    t.float "threshold_used"
    t.datetime "updated_at", null: false
    t.boolean "within_threshold"
    t.index ["baseline_id"], name: "index_comparisons_on_baseline_id"
    t.index ["review_status"], name: "index_comparisons_on_review_status"
    t.index ["snapshot_id"], name: "index_comparisons_on_snapshot_id"
    t.index ["test_run_id", "status"], name: "index_comparisons_on_test_run_id_and_status"
    t.index ["test_run_id"], name: "index_comparisons_on_test_run_id"
  end

  create_table "pages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "actions", default: []
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true
    t.string "hide_selectors", default: [], array: true
    t.string "mask_selectors", default: [], array: true
    t.string "name", null: false
    t.string "path", null: false
    t.integer "position", default: 0
    t.uuid "project_id", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.jsonb "viewport"
    t.jsonb "wait_for"
    t.integer "wait_ms"
    t.index ["project_id", "enabled"], name: "index_pages_on_project_id_and_enabled"
    t.index ["project_id", "path"], name: "index_pages_on_project_id_and_path"
    t.index ["project_id", "slug"], name: "index_pages_on_project_id_and_slug", unique: true
    t.index ["project_id"], name: "index_pages_on_project_id"
  end

  create_table "projects", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.float "apdex_t", default: 0.5
    t.jsonb "auth_config", default: {}
    t.string "base_url", null: false
    t.datetime "created_at", null: false
    t.string "environment", default: "production"
    t.string "name", null: false
    t.string "platform_project_id", null: false
    t.jsonb "settings", default: {}
    t.string "staging_url"
    t.datetime "updated_at", null: false
    t.index ["platform_project_id"], name: "index_projects_on_platform_project_id", unique: true
  end

  create_table "snapshots", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "branch"
    t.uuid "browser_config_id", null: false
    t.integer "capture_duration_ms"
    t.datetime "captured_at"
    t.string "commit_sha"
    t.datetime "created_at", null: false
    t.string "environment"
    t.integer "file_size"
    t.integer "height"
    t.jsonb "metadata", default: {}
    t.uuid "page_id", null: false
    t.string "screenshot_key"
    t.string "status", default: "pending"
    t.uuid "test_run_id"
    t.string "thumbnail_key"
    t.string "triggered_by"
    t.datetime "updated_at", null: false
    t.integer "width"
    t.index ["browser_config_id"], name: "index_snapshots_on_browser_config_id"
    t.index ["page_id", "captured_at"], name: "index_snapshots_on_page_id_and_captured_at"
    t.index ["page_id"], name: "index_snapshots_on_page_id"
    t.index ["test_run_id", "page_id"], name: "index_snapshots_on_test_run_id_and_page_id"
    t.index ["test_run_id", "status"], name: "index_snapshots_on_test_run_id_and_status"
    t.index ["test_run_id"], name: "index_snapshots_on_test_run_id"
  end

  create_table "test_cases", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled", default: true
    t.string "name", null: false
    t.integer "position", default: 0
    t.uuid "project_id", null: false
    t.jsonb "steps", default: []
    t.string "tags", default: [], array: true
    t.datetime "updated_at", null: false
    t.index ["project_id", "enabled"], name: "index_test_cases_on_project_id_and_enabled"
    t.index ["project_id", "name"], name: "index_test_cases_on_project_id_and_name"
    t.index ["project_id"], name: "index_test_cases_on_project_id"
  end

  create_table "test_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "base_branch"
    t.string "branch"
    t.string "commit_message"
    t.string "commit_sha"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "environment"
    t.integer "error_count", default: 0
    t.integer "failed_count", default: 0
    t.jsonb "notification_channels", default: []
    t.boolean "notified", default: false
    t.integer "passed_count", default: 0
    t.integer "pending_count", default: 0
    t.string "pr_number"
    t.string "pr_url"
    t.uuid "project_id", null: false
    t.datetime "started_at"
    t.string "status", default: "pending"
    t.integer "total_pages", default: 0
    t.string "trigger_source"
    t.string "triggered_by"
    t.datetime "updated_at", null: false
    t.index ["project_id", "branch"], name: "index_test_runs_on_project_id_and_branch"
    t.index ["project_id", "created_at"], name: "index_test_runs_on_project_id_and_created_at"
    t.index ["project_id", "pr_number"], name: "index_test_runs_on_project_id_and_pr_number"
    t.index ["project_id", "status"], name: "index_test_runs_on_project_id_and_status"
    t.index ["project_id"], name: "index_test_runs_on_project_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "baselines", "browser_configs"
  add_foreign_key "baselines", "pages"
  add_foreign_key "browser_configs", "projects"
  add_foreign_key "comparisons", "baselines"
  add_foreign_key "comparisons", "snapshots"
  add_foreign_key "comparisons", "test_runs"
  add_foreign_key "pages", "projects"
  add_foreign_key "snapshots", "browser_configs"
  add_foreign_key "snapshots", "pages"
  add_foreign_key "snapshots", "test_runs"
  add_foreign_key "test_cases", "projects"
  add_foreign_key "test_runs", "projects"
end
