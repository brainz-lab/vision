require "rails_helper"

RSpec.describe "API::V1::Projects", type: :request do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("VISION_MASTER_KEY").and_return("test_master_key_vision")
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("VISION_MASTER_KEY", anything).and_return("test_master_key_vision")
  end

  describe "POST /api/v1/projects/provision" do
    let(:headers) { master_key_headers }

    it "creates a new project with platform_project_id" do
      expect {
        post "/api/v1/projects/provision",
             params: { platform_project_id: "plat_new_123", name: "My App", base_url: "https://myapp.com" },
             headers: headers
      }.to change(Project, :count).by(1)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["platform_project_id"]).to eq("plat_new_123")
      expect(body["name"]).to eq("My App")
      expect(body["ingest_key"]).to start_with("vis_ingest_")
      expect(body["api_key"]).to start_with("vis_api_")
    end

    it "returns 200 for existing project (idempotent)" do
      create(:project, platform_project_id: "plat_existing")
      post "/api/v1/projects/provision",
           params: { platform_project_id: "plat_existing" },
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(Project.where(platform_project_id: "plat_existing").count).to eq(1)
    end

    it "creates standalone project by name when no platform_project_id" do
      expect {
        post "/api/v1/projects/provision",
             params: { name: "Standalone Project" },
             headers: headers
      }.to change(Project, :count).by(1)

      body = JSON.parse(response.body)
      expect(body["name"]).to eq("Standalone Project")
      expect(body["platform_project_id"]).to start_with("vis_")
    end

    it "returns 400 when neither platform_project_id nor name provided" do
      post "/api/v1/projects/provision", headers: headers
      expect(response).to have_http_status(:bad_request)
    end

    it "returns 401 without master key" do
      post "/api/v1/projects/provision",
           params: { platform_project_id: "plat_xyz", name: "App" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 with wrong master key" do
      post "/api/v1/projects/provision",
           params: { platform_project_id: "plat_xyz", name: "App" },
           headers: { "X-Master-Key" => "wrong_key" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/projects/lookup" do
    let!(:project) { create(:project, platform_project_id: "plat_lookup_abc", name: "Lookup Project") }

    it "returns project by platform_project_id" do
      get "/api/v1/projects/lookup", params: { platform_project_id: "plat_lookup_abc" }
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["platform_project_id"]).to eq("plat_lookup_abc")
    end

    it "returns project by name" do
      get "/api/v1/projects/lookup", params: { name: "Lookup Project" }
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for unknown project" do
      get "/api/v1/projects/lookup", params: { platform_project_id: "plat_unknown" }
      expect(response).to have_http_status(:not_found)
    end
  end
end
