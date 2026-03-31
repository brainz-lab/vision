require "rails_helper"

RSpec.describe "API::V1::Snapshots", type: :request do
  let(:project)        { create(:project) }
  let(:browser_config) { create(:browser_config, project: project) }
  let(:page)           { create(:page, project: project) }
  let(:headers)        { auth_headers(project) }

  before do
    browser_config
    allow(CaptureScreenshotJob).to receive(:perform_later)
  end

  describe "GET /api/v1/snapshots" do
    let!(:snap1) { create(:snapshot, page: page, browser_config: browser_config, branch: "main") }
    let!(:snap2) { create(:snapshot, :captured, page: page, browser_config: browser_config, branch: "feature") }

    it "returns snapshots for the project" do
      get "/api/v1/snapshots", headers: headers
      body = JSON.parse(response.body)
      ids  = body["snapshots"].map { |s| s["id"] }
      expect(ids).to include(snap1.id, snap2.id)
    end

    it "returns snapshots regardless of branch param (no filtering implemented)" do
      get "/api/v1/snapshots", params: { branch: "feature" }, headers: headers
      body = JSON.parse(response.body)
      ids  = body["snapshots"].map { |s| s["id"] }
      expect(ids).to include(snap2.id)
    end

    it "returns snapshots regardless of status param (no filtering implemented)" do
      get "/api/v1/snapshots", params: { status: "captured" }, headers: headers
      body = JSON.parse(response.body)
      ids  = body["snapshots"].map { |s| s["id"] }
      expect(ids).to include(snap2.id)
    end

    it "does not return snapshots from other projects" do
      other_project = create(:project)
      other_page    = create(:page, project: other_project)
      other_config  = create(:browser_config, project: other_project)
      other_snap    = create(:snapshot, page: other_page, browser_config: other_config)
      get "/api/v1/snapshots", headers: headers
      body = JSON.parse(response.body)
      ids  = body["snapshots"].map { |s| s["id"] }
      expect(ids).not_to include(other_snap.id)
    end

    context "without authentication" do
      it "returns 401" do
        get "/api/v1/snapshots"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /api/v1/snapshots" do
    let(:valid_params) do
      { page_id: page.id, browser_config_id: browser_config.id, branch: "main" }
    end

    it "creates a new snapshot and queues capture job" do
      expect {
        post "/api/v1/snapshots", params: valid_params, headers: headers
      }.to change(Snapshot, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(CaptureScreenshotJob).to have_received(:perform_later)
    end

    it "returns snapshot with pending status" do
      post "/api/v1/snapshots", params: valid_params, headers: headers
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("pending")
    end
  end

  describe "GET /api/v1/snapshots/:id" do
    let!(:snapshot) { create(:snapshot, page: page, browser_config: browser_config) }

    it "returns snapshot details with comparison key when comparison exists" do
      comparison = create(:comparison, snapshot: snapshot, baseline: create(:baseline, page: page, browser_config: browser_config))
      get "/api/v1/snapshots/#{snapshot.id}", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq(snapshot.id)
      expect(body).to have_key("comparison")
    end

    it "returns 404 for unknown snapshot" do
      get "/api/v1/snapshots/#{SecureRandom.uuid}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/snapshots/:id/compare" do
    let!(:snapshot) { create(:snapshot, :captured, page: page, browser_config: browser_config) }

    before do
      allow(CompareScreenshotsJob).to receive(:perform_later)
    end

    it "queues a comparison job" do
      post "/api/v1/snapshots/#{snapshot.id}/compare", headers: headers
      expect(CompareScreenshotsJob).to have_received(:perform_later).with(snapshot.id)
    end
  end
end
