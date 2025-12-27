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

ActiveRecord::Schema[8.1].define(version: 2025_12_27_100004) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"
  enable_extension "timescaledb"

  create_table "action_cache_entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "action_data", default: {}, null: false
    t.string "action_type", null: false
    t.float "avg_duration_ms"
    t.jsonb "context", default: {}
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.integer "failure_count", default: 0
    t.string "instruction_hash"
    t.datetime "last_used_at"
    t.uuid "project_id", null: false
    t.integer "success_count", default: 1
    t.datetime "updated_at", null: false
    t.string "url_pattern", null: false
    t.index ["expires_at"], name: "index_action_cache_entries_on_expires_at"
    t.index ["last_used_at"], name: "index_action_cache_entries_on_last_used_at"
    t.index ["project_id", "instruction_hash"], name: "index_action_cache_entries_on_project_id_and_instruction_hash"
    t.index ["project_id", "url_pattern", "action_type"], name: "idx_on_project_id_url_pattern_action_type_1a90e4efc9"
    t.index ["project_id"], name: "index_action_cache_entries_on_project_id"
  end

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

  create_table "ai_tasks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "browser_provider", default: "local", null: false
    t.boolean "capture_screenshots", default: true
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.text "error_message"
    t.jsonb "extracted_data", default: {}
    t.string "final_url"
    t.text "instruction", null: false
    t.integer "max_steps", default: 25
    t.jsonb "metadata", default: {}
    t.string "model", default: "claude-sonnet-4", null: false
    t.uuid "project_id", null: false
    t.text "result"
    t.string "start_url"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.integer "steps_executed", default: 0
    t.boolean "stop_requested", default: false
    t.integer "timeout_seconds", default: 300
    t.string "triggered_by"
    t.datetime "updated_at", null: false
    t.jsonb "viewport", default: {"width" => 1280, "height" => 720}
    t.index ["project_id", "created_at"], name: "index_ai_tasks_on_project_id_and_created_at"
    t.index ["project_id", "status"], name: "index_ai_tasks_on_project_id_and_status"
    t.index ["project_id"], name: "index_ai_tasks_on_project_id"
    t.index ["status"], name: "index_ai_tasks_on_status"
    t.index ["triggered_by"], name: "index_ai_tasks_on_triggered_by"
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

  create_table "browser_sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "browser_provider", default: "local", null: false
    t.datetime "closed_at"
    t.string "connect_url"
    t.datetime "created_at", null: false
    t.string "current_title"
    t.string "current_url"
    t.datetime "expires_at"
    t.jsonb "metadata", default: {}
    t.uuid "project_id", null: false
    t.string "provider_session_id", null: false
    t.string "start_url"
    t.string "status", default: "initializing", null: false
    t.datetime "updated_at", null: false
    t.jsonb "viewport", default: {"width" => 1280, "height" => 720}
    t.string "websocket_url"
    t.index ["expires_at"], name: "index_browser_sessions_on_expires_at"
    t.index ["project_id", "status"], name: "index_browser_sessions_on_project_id_and_status"
    t.index ["project_id"], name: "index_browser_sessions_on_project_id"
    t.index ["provider_session_id"], name: "index_browser_sessions_on_provider_session_id", unique: true
    t.index ["status"], name: "index_browser_sessions_on_status"
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

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "task_steps", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action", null: false
    t.jsonb "action_data", default: {}
    t.uuid "ai_task_id", null: false
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.text "error_message"
    t.datetime "executed_at"
    t.integer "position", null: false
    t.text "reasoning"
    t.string "selector"
    t.boolean "success", default: true
    t.datetime "updated_at", null: false
    t.string "url_after"
    t.string "url_before"
    t.text "value"
    t.index ["ai_task_id", "position"], name: "index_task_steps_on_ai_task_id_and_position"
    t.index ["ai_task_id", "success"], name: "index_task_steps_on_ai_task_id_and_success"
    t.index ["ai_task_id"], name: "index_task_steps_on_ai_task_id"
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

  add_foreign_key "action_cache_entries", "projects"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "ai_tasks", "projects"
  add_foreign_key "baselines", "browser_configs"
  add_foreign_key "baselines", "pages"
  add_foreign_key "browser_configs", "projects"
  add_foreign_key "browser_sessions", "projects"
  add_foreign_key "comparisons", "baselines"
  add_foreign_key "comparisons", "snapshots"
  add_foreign_key "comparisons", "test_runs"
  add_foreign_key "pages", "projects"
  add_foreign_key "snapshots", "browser_configs"
  add_foreign_key "snapshots", "pages"
  add_foreign_key "snapshots", "test_runs"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "task_steps", "ai_tasks"
  add_foreign_key "test_cases", "projects"
  add_foreign_key "test_runs", "projects"
end
