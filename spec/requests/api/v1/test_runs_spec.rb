require "rails_helper"

RSpec.describe "API::V1::TestRuns", type: :request do
  let(:project) { create(:project) }
  let(:headers) { auth_headers(project) }

  before do
    allow(CaptureScreenshotJob).to receive(:perform_later)
  end

  describe "GET /api/v1/test_runs" do
    let!(:run1) { create(:test_run, :passed, project: project) }
    let!(:run2) { create(:test_run, :failed, project: project) }
    let!(:run3) { create(:test_run, project: project, branch: "feature") }

    it "returns all test runs for the project" do
      get "/api/v1/test_runs", headers: headers
      body = JSON.parse(response.body)
      ids  = body["test_runs"].map { |r| r["id"] }
      expect(ids).to include(run1.id, run2.id, run3.id)
    end

    it "filters by branch" do
      get "/api/v1/test_runs", params: { branch: "feature" }, headers: headers
      body = JSON.parse(response.body)
      ids  = body["test_runs"].map { |r| r["id"] }
      expect(ids).to include(run3.id)
      expect(ids).not_to include(run1.id)
    end

    it "filters by status" do
      get "/api/v1/test_runs", params: { status: "passed" }, headers: headers
      body = JSON.parse(response.body)
      ids  = body["test_runs"].map { |r| r["id"] }
      expect(ids).to include(run1.id)
      expect(ids).not_to include(run2.id)
    end

    it "does not return runs from other projects" do
      other     = create(:project)
      other_run = create(:test_run, project: other)
      get "/api/v1/test_runs", headers: headers
      body = JSON.parse(response.body)
      ids  = body["test_runs"].map { |r| r["id"] }
      expect(ids).not_to include(other_run.id)
    end

    context "without authentication" do
      it "returns 401" do
        get "/api/v1/test_runs"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /api/v1/test_runs" do
    let(:valid_params) { { branch: "main", environment: "staging", triggered_by: "ci" } }

    it "creates a test run and starts it" do
      expect {
        post "/api/v1/test_runs", params: valid_params, headers: headers
      }.to change(TestRun, :count).by(1)

      expect(response).to have_http_status(:created)
    end

    it "returns test run in response" do
      post "/api/v1/test_runs", params: valid_params, headers: headers
      body = JSON.parse(response.body)
      expect(body).to have_key("id")
      expect(body).to have_key("status")
    end
  end

  describe "GET /api/v1/test_runs/:id" do
    let!(:test_run) { create(:test_run, :passed, project: project) }

    it "returns test run details with comparisons" do
      get "/api/v1/test_runs/#{test_run.id}", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq(test_run.id)
      expect(body).to have_key("summary")
      expect(body).to have_key("comparisons")
    end

    it "returns 404 for unknown test run" do
      get "/api/v1/test_runs/#{SecureRandom.uuid}", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for test run from another project" do
      other     = create(:project)
      other_run = create(:test_run, project: other)
      get "/api/v1/test_runs/#{other_run.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
