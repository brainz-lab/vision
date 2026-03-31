require "rails_helper"

RSpec.describe "API::V1::Sessions", type: :request do
  let(:project) { create(:project) }
  let(:headers) { auth_headers(project) }

  # Mock the BrowserProviders::Factory to avoid real browser connections
  let(:mock_provider) do
    double("BrowserProvider",
      create_session: { session_id: "sess_mock_#{SecureRandom.hex(8)}", live_url: nil },
      close_session:  true,
      navigate:       { url: "https://example.com", title: "Example" },
      screenshot:     { data: "raw_png_data", content_type: "image/png" },
      page_content:   "<html><body>Hello</body></html>",
      perform_action: { success: true },
      execute_ai_action: { action: "click", selector: "#btn", success: true, reasoning: "Found the button" },
      current_url:    "https://example.com",
      current_title:  "Example Page"
    )
  end

  before do
    allow(BrowserProviders::Factory).to receive(:for).and_return(mock_provider)
    allow(BrowserProviders::Factory).to receive(:for_project).and_return(mock_provider)
  end

  describe "GET /api/v1/sessions" do
    let!(:active_session) { create(:browser_session, project: project, status: "active") }
    let!(:closed_session) { create(:browser_session, :closed, project: project) }

    it "returns active sessions for the project" do
      get "/api/v1/sessions", headers: headers
      body = JSON.parse(response.body)
      ids  = body["sessions"].map { |s| s["id"] }
      expect(ids).to include(active_session.id)
    end

    it "does not return sessions from other projects" do
      other         = create(:project)
      other_session = create(:browser_session, project: other)
      get "/api/v1/sessions", headers: headers
      body = JSON.parse(response.body)
      ids  = body["sessions"].map { |s| s["id"] }
      expect(ids).not_to include(other_session.id)
    end

    context "without authentication" do
      it "returns 401" do
        get "/api/v1/sessions"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /api/v1/sessions" do
    let(:valid_params) do
      { browser_provider: "local", viewport: { width: 1280, height: 720 } }
    end

    it "creates a new browser session" do
      expect {
        post "/api/v1/sessions", params: valid_params, headers: headers
      }.to change(BrowserSession, :count).by(1)

      expect(response).to have_http_status(:created)
    end
  end

  describe "GET /api/v1/sessions/:id" do
    let!(:session) { create(:browser_session, :with_url, project: project) }

    it "returns session details" do
      get "/api/v1/sessions/#{session.id}", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["session"]["id"]).to eq(session.id)
      expect(body["session"]).to have_key("status")
      expect(body["session"]).to have_key("browser_provider")
    end

    it "returns 404 for unknown session" do
      get "/api/v1/sessions/#{SecureRandom.uuid}", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for session from another project" do
      other         = create(:project)
      other_session = create(:browser_session, project: other)
      get "/api/v1/sessions/#{other_session.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/sessions/:id" do
    let!(:session) { create(:browser_session, project: project, status: "active") }

    it "closes the session" do
      delete "/api/v1/sessions/#{session.id}", headers: headers
      expect(response).to have_http_status(:ok).or have_http_status(:no_content)
    end
  end

  describe "GET /api/v1/sessions/:id/screenshot" do
    let!(:session) { create(:browser_session, project: project, status: "active") }

    it "returns screenshot data" do
      get "/api/v1/sessions/#{session.id}/screenshot", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to have_key("data")
    end
  end

  describe "GET /api/v1/sessions/:id/state" do
    let!(:session) { create(:browser_session, :with_url, project: project, status: "active") }

    it "returns current page state" do
      get "/api/v1/sessions/#{session.id}/state", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to have_key("url")
    end
  end
end
