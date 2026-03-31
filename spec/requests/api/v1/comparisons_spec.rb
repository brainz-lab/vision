require "rails_helper"

RSpec.describe "API::V1::Comparisons", type: :request do
  let(:project)        { create(:project) }
  let(:browser_config) { create(:browser_config, project: project) }
  let(:page)           { create(:page, project: project) }
  let(:baseline)       { create(:baseline, page: page, browser_config: browser_config) }
  let(:snapshot)       { create(:snapshot, :captured, page: page, browser_config: browser_config) }
  let(:headers)        { auth_headers(project) }

  describe "GET /api/v1/comparisons/:id" do
    let!(:comparison) { create(:comparison, :failed, baseline: baseline, snapshot: snapshot) }

    it "returns comparison details" do
      get "/api/v1/comparisons/#{comparison.id}", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq(comparison.id)
      expect(body).to have_key("diff_percentage")
      expect(body).to have_key("status")
    end

    it "returns 404 for unknown comparison" do
      get "/api/v1/comparisons/#{SecureRandom.uuid}", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for comparison from another project" do
      other         = create(:project)
      other_page    = create(:page, project: other)
      other_config  = create(:browser_config, project: other)
      other_baseline = create(:baseline, page: other_page, browser_config: other_config)
      other_snapshot = create(:snapshot, page: other_page, browser_config: other_config)
      other_comp     = create(:comparison, :failed, baseline: other_baseline, snapshot: other_snapshot)
      get "/api/v1/comparisons/#{other_comp.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    context "without authentication" do
      it "returns 401" do
        get "/api/v1/comparisons/#{comparison.id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /api/v1/comparisons/:id/approve" do
    let!(:comparison) { create(:comparison, :failed, baseline: baseline, snapshot: snapshot) }

    it "approves the comparison" do
      post "/api/v1/comparisons/#{comparison.id}/approve",
           params: { user_email: "reviewer@example.com" },
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(comparison.reload.review_status).to eq("approved")
      expect(comparison.reviewed_by).to eq("reviewer@example.com")
    end

    it "updates baseline when update_baseline is true" do
      allow_any_instance_of(Snapshot).to receive(:promote_to_baseline!).and_return(double("baseline"))

      post "/api/v1/comparisons/#{comparison.id}/approve",
           params: { user_email: "admin@example.com", update_baseline: "true" },
           headers: headers

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /api/v1/comparisons/:id/reject" do
    let!(:comparison) { create(:comparison, :failed, baseline: baseline, snapshot: snapshot) }

    it "rejects the comparison with notes" do
      post "/api/v1/comparisons/#{comparison.id}/reject",
           params: { user_email: "reviewer@example.com", notes: "Regression found" },
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(comparison.reload.review_status).to eq("rejected")
      expect(comparison.review_notes).to eq("Regression found")
    end
  end
end
