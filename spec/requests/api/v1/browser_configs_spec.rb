require "rails_helper"

RSpec.describe "API::V1::BrowserConfigs", type: :request do
  let(:project) { create(:project) }
  let(:headers) { auth_headers(project) }

  describe "GET /api/v1/browser_configs" do
    let!(:config1) { create(:browser_config, project: project) }
    let!(:config2) { create(:browser_config, :mobile, project: project) }

    it "returns all browser configs for the project" do
      get "/api/v1/browser_configs", headers: headers
      body = JSON.parse(response.body)
      ids = body["browser_configs"].map { |c| c["id"] }
      expect(ids).to include(config1.id, config2.id)
    end

    it "does not return configs from other projects" do
      other         = create(:project)
      other_config  = create(:browser_config, project: other)
      get "/api/v1/browser_configs", headers: headers
      body = JSON.parse(response.body)
      ids  = body["browser_configs"].map { |c| c["id"] }
      expect(ids).not_to include(other_config.id)
    end

    context "without authentication" do
      it "returns 401" do
        get "/api/v1/browser_configs"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /api/v1/browser_configs" do
    let(:valid_params) do
      { browser: "firefox", name: "Firefox Desktop", width: 1280, height: 800 }
    end

    it "creates a new browser config and returns 201" do
      expect {
        post "/api/v1/browser_configs", params: valid_params, headers: headers
      }.to change(BrowserConfig, :count).by(1)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["browser"]).to eq("firefox")
      expect(body["name"]).to eq("Firefox Desktop")
    end

    it "returns 422 for invalid browser" do
      post "/api/v1/browser_configs",
           params: { browser: "edge", name: "Edge", width: 1280, height: 720 },
           headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /api/v1/browser_configs/:id" do
    let!(:config) { create(:browser_config, project: project) }

    it "returns browser config details" do
      get "/api/v1/browser_configs/#{config.id}", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq(config.id)
      expect(body).to have_key("width")
      expect(body).to have_key("height")
    end

    it "returns 404 for unknown config" do
      get "/api/v1/browser_configs/#{SecureRandom.uuid}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/v1/browser_configs/:id" do
    let!(:config) { create(:browser_config, project: project, name: "Old Config") }

    it "updates the browser config" do
      patch "/api/v1/browser_configs/#{config.id}",
            params: { name: "New Config" },
            headers: headers
      expect(response).to have_http_status(:ok)
      expect(config.reload.name).to eq("New Config")
    end
  end

  describe "DELETE /api/v1/browser_configs/:id" do
    let!(:config) { create(:browser_config, project: project) }

    it "deletes the config and returns 204" do
      expect {
        delete "/api/v1/browser_configs/#{config.id}", headers: headers
      }.to change(BrowserConfig, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end
  end
end
