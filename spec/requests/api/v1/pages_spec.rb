require "rails_helper"

RSpec.describe "API::V1::Pages", type: :request do
  let(:project) { create(:project) }
  let(:headers) { auth_headers(project) }

  describe "GET /api/v1/pages" do
    let!(:page1) { create(:page, project: project, enabled: true) }
    let!(:page2) { create(:page, project: project, enabled: false) }

    it "returns all pages for the project" do
      get "/api/v1/pages", headers: headers
      body = JSON.parse(response.body)
      ids = body["pages"].map { |p| p["id"] }
      expect(ids).to include(page1.id, page2.id)
    end

    it "does not return pages from other projects" do
      other_project = create(:project)
      other_page    = create(:page, project: other_project)
      get "/api/v1/pages", headers: headers
      body = JSON.parse(response.body)
      ids  = body["pages"].map { |p| p["id"] }
      expect(ids).not_to include(other_page.id)
    end

    context "without authentication" do
      it "returns 401" do
        get "/api/v1/pages"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /api/v1/pages" do
    let(:valid_params) do
      { page: { name: "Home Page", path: "/", enabled: true } }
    end

    it "creates a new page and returns 201" do
      expect {
        post "/api/v1/pages", params: valid_params, headers: headers
      }.to change(Page, :count).by(1)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["name"]).to eq("Home Page")
      expect(body["path"]).to eq("/")
    end

    it "returns 422 for invalid params" do
      post "/api/v1/pages",
           params: { page: { name: "", path: "" } },
           headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /api/v1/pages/:id" do
    let!(:page) { create(:page, project: project) }

    it "returns page details with baselines" do
      get "/api/v1/pages/#{page.id}", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq(page.id)
      expect(body).to have_key("baselines")
    end

    it "returns 404 for unknown page" do
      get "/api/v1/pages/#{SecureRandom.uuid}", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for page from another project" do
      other = create(:project)
      other_page = create(:page, project: other)
      get "/api/v1/pages/#{other_page.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/v1/pages/:id" do
    let!(:page) { create(:page, project: project, name: "Old Name") }

    it "updates the page" do
      patch "/api/v1/pages/#{page.id}",
            params: { page: { name: "New Name" } },
            headers: headers
      expect(response).to have_http_status(:ok)
      expect(page.reload.name).to eq("New Name")
    end
  end

  describe "DELETE /api/v1/pages/:id" do
    let!(:page) { create(:page, project: project) }

    it "deletes the page and returns 204" do
      expect {
        delete "/api/v1/pages/#{page.id}", headers: headers
      }.to change(Page, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end
  end
end
