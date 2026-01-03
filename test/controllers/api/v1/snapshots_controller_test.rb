# frozen_string_literal: true

require "test_helper"

class Api::V1::SnapshotsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:main_project)
    # Set up Vision key for authentication
    @api_key = "vis_ingest_#{SecureRandom.hex(16)}"
    @project.update!(settings: @project.settings.merge("ingest_key" => @api_key))

    @page = pages(:homepage)
    @browser_config = browser_configs(:chrome_desktop)
  end

  # ============================================
  # Authentication Tests
  # ============================================

  test "GET index requires authentication" do
    get api_v1_snapshots_url

    assert_response :unauthorized
    assert_includes response.parsed_body["error"], "Invalid API key"
  end

  test "GET index with invalid API key returns unauthorized" do
    get api_v1_snapshots_url, headers: { "Authorization" => "Bearer invalid_key" }

    assert_response :unauthorized
  end

  test "GET index with valid Vision key authenticates" do
    get api_v1_snapshots_url, headers: auth_headers

    assert_response :success
  end

  test "authentication via X-API-Key header" do
    get api_v1_snapshots_url, headers: { "X-API-Key" => @api_key }

    assert_response :success
  end

  test "authentication via api_key query parameter" do
    get api_v1_snapshots_url(api_key: @api_key)

    assert_response :success
  end

  # ============================================
  # GET /api/v1/snapshots (Index)
  # ============================================

  test "GET index returns snapshots for project" do
    get api_v1_snapshots_url, headers: auth_headers

    assert_response :success

    body = response.parsed_body
    assert body.key?("snapshots")
    assert_kind_of Array, body["snapshots"]
  end

  test "GET index with page_id filters by page" do
    get api_v1_snapshots_url(page_id: @page.id), headers: auth_headers

    assert_response :success

    body = response.parsed_body
    body["snapshots"].each do |snapshot|
      assert_equal @page.id, snapshot["page_id"]
    end
  end

  test "GET index respects limit parameter" do
    get api_v1_snapshots_url(limit: 2), headers: auth_headers

    assert_response :success

    body = response.parsed_body
    assert body["snapshots"].length <= 2
  end

  test "GET index returns recent snapshots first" do
    get api_v1_snapshots_url, headers: auth_headers

    assert_response :success

    body = response.parsed_body
    timestamps = body["snapshots"].map { |s| s["captured_at"] }.compact
    # Recent should be first
    assert_equal timestamps, timestamps.sort.reverse
  end

  # ============================================
  # GET /api/v1/snapshots/:id (Show)
  # ============================================

  test "GET show returns snapshot details" do
    snapshot = snapshots(:captured_snapshot)

    get api_v1_snapshot_url(snapshot), headers: auth_headers

    assert_response :success

    body = response.parsed_body
    assert_equal snapshot.id, body["id"]
    assert_equal snapshot.page.name, body["page_name"]
    assert_equal snapshot.browser_config.name, body["browser_config_name"]
    assert_equal snapshot.status, body["status"]
  end

  test "GET show returns 404 for non-existent snapshot" do
    get api_v1_snapshot_url(id: SecureRandom.uuid), headers: auth_headers

    assert_response :not_found
  end

  test "GET show includes comparison when available" do
    snapshot = snapshots(:compared_snapshot)
    # Create comparison for this snapshot
    comparison = comparisons(:passed_comparison)
    comparison.update!(snapshot: snapshot)

    get api_v1_snapshot_url(snapshot), headers: auth_headers

    assert_response :success

    body = response.parsed_body
    assert body.key?("comparison")
    assert body["comparison"]["status"].present?
  end

  # ============================================
  # POST /api/v1/snapshots (Create)
  # ============================================

  test "POST create creates snapshot with page_id" do
    assert_difference "Snapshot.count", 1 do
      post api_v1_snapshots_url,
        params: {
          page_id: @page.id,
          branch: "feature/test",
          commit_sha: "abc123",
          environment: "staging"
        },
        headers: auth_headers
    end

    assert_response :created

    body = response.parsed_body
    assert_equal @page.id, body["page_id"]
    assert_equal "feature/test", body["branch"]
    assert_equal "abc123", body["commit_sha"]
    assert_equal "staging", body["environment"]
    assert_equal "pending", body["status"]
  end

  test "POST create creates page from URL if not exists" do
    new_url = "https://example.com/new-page"

    assert_difference [ "Snapshot.count", "Page.count" ], 1 do
      post api_v1_snapshots_url,
        params: {
          url: new_url,
          name: "New Page"
        },
        headers: auth_headers
    end

    assert_response :created

    body = response.parsed_body
    page = Page.find(body["page_id"])
    assert_equal "/new-page", page.path
    assert_equal "New Page", page.name
  end

  test "POST create uses existing page for URL" do
    existing_page = pages(:homepage)

    assert_difference "Snapshot.count", 1 do
      assert_no_difference "Page.count" do
        post api_v1_snapshots_url,
          params: {
            url: existing_page.full_url
          },
          headers: auth_headers
      end
    end

    assert_response :created
  end

  test "POST create uses specified browser_config" do
    mobile_config = browser_configs(:chrome_mobile)

    post api_v1_snapshots_url,
      params: {
        page_id: @page.id,
        browser_config_id: mobile_config.id
      },
      headers: auth_headers

    assert_response :created

    body = response.parsed_body
    assert_equal mobile_config.id, body["browser_config_id"]
    assert_equal mobile_config.name, body["browser_config_name"]
  end

  test "POST create uses default browser_config when not specified" do
    post api_v1_snapshots_url,
      params: { page_id: @page.id },
      headers: auth_headers

    assert_response :created

    body = response.parsed_body
    assert_not_nil body["browser_config_id"]
  end

  test "POST create queues CaptureScreenshotJob" do
    assert_enqueued_with(job: CaptureScreenshotJob) do
      post api_v1_snapshots_url,
        params: { page_id: @page.id },
        headers: auth_headers
    end
  end

  test "POST create defaults environment to staging" do
    post api_v1_snapshots_url,
      params: { page_id: @page.id },
      headers: auth_headers

    assert_response :created

    body = response.parsed_body
    assert_equal "staging", body["environment"]
  end

  # ============================================
  # POST /api/v1/snapshots/:id/compare
  # ============================================

  test "POST compare queues comparison job" do
    snapshot = snapshots(:captured_snapshot)

    assert_enqueued_with(job: CompareScreenshotsJob) do
      post compare_api_v1_snapshot_url(snapshot), headers: auth_headers
    end

    assert_response :success

    body = response.parsed_body
    assert_equal "Comparison queued", body["message"]
    assert_equal snapshot.id, body["snapshot_id"]
  end

  test "POST compare fails for pending snapshot" do
    snapshot = snapshots(:pending_snapshot)

    post compare_api_v1_snapshot_url(snapshot), headers: auth_headers

    assert_response :unprocessable_entity

    body = response.parsed_body
    assert_includes body["error"], "not yet captured"
  end

  test "POST compare fails for error snapshot" do
    snapshot = snapshots(:error_snapshot)

    post compare_api_v1_snapshot_url(snapshot), headers: auth_headers

    assert_response :unprocessable_entity
  end

  # ============================================
  # Response Format Tests
  # ============================================

  test "snapshot response includes all expected fields" do
    post api_v1_snapshots_url,
      params: {
        page_id: @page.id,
        branch: "main",
        commit_sha: "def456",
        environment: "production"
      },
      headers: auth_headers

    assert_response :created

    body = response.parsed_body

    assert body.key?("id")
    assert body.key?("page_id")
    assert body.key?("page_name")
    assert body.key?("browser_config_id")
    assert body.key?("browser_config_name")
    assert body.key?("branch")
    assert body.key?("commit_sha")
    assert body.key?("environment")
    assert body.key?("status")
    assert body.key?("captured_at")
    assert body.key?("capture_duration_ms")
    assert body.key?("screenshot_url")
    assert body.key?("thumbnail_url")
    assert body.key?("width")
    assert body.key?("height")
  end

  # ============================================
  # Error Handling Tests
  # ============================================

  test "returns 404 for snapshot from different project" do
    other_project = projects(:secondary_project)
    other_page = pages(:secondary_home)

    # Create snapshot for different project
    other_snapshot = Snapshot.create!(
      page: other_page,
      browser_config: browser_configs(:secondary_chrome),
      status: "captured"
    )

    get api_v1_snapshot_url(other_snapshot), headers: auth_headers

    assert_response :not_found
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@api_key}" }
  end
end
