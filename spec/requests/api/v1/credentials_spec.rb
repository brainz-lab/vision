require "rails_helper"

RSpec.describe "API::V1::Credentials", type: :request do
  let(:project) { create(:project) }
  let(:headers) { auth_headers(project) }

  # Mock VaultClient to avoid actual Vault calls
  let(:mock_vault_client) do
    double("VaultClient",
      set_credential: { path: "/projects/test/credentials/github" },
      get_credential: { username: "user", password: "secret" }
    )
  end

  before do
    allow(VaultClient).to receive(:for_project).and_return(mock_vault_client)
  end

  describe "GET /api/v1/credentials" do
    let!(:cred1) { create(:credential, project: project, name: "github") }
    let!(:cred2) { create(:credential, :api_key, project: project, name: "stripe-key") }

    it "returns all credentials for the project" do
      get "/api/v1/credentials", headers: headers
      body = JSON.parse(response.body)
      ids  = body["credentials"].map { |c| c["id"] }
      expect(ids).to include(cred1.id, cred2.id)
    end

    it "never returns actual credential values" do
      get "/api/v1/credentials", headers: headers
      body = JSON.parse(response.body)
      body["credentials"].each do |cred|
        expect(cred).not_to have_key("password")
        expect(cred).not_to have_key("secret")
      end
    end

    it "does not return credentials from other projects" do
      other      = create(:project)
      other_cred = create(:credential, project: other, name: "other-cred")
      get "/api/v1/credentials", headers: headers
      body = JSON.parse(response.body)
      ids  = body["credentials"].map { |c| c["id"] }
      expect(ids).not_to include(other_cred.id)
    end

    context "without authentication" do
      it "returns 401" do
        get "/api/v1/credentials"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /api/v1/credentials" do
    let(:valid_params) do
      {
        name:            "my-service",
        credential_type: "login",
        service_url:     "https://myservice.com/*",
        username:        "admin",
        password:        "secret123"
      }
    end

    it "creates a new credential and stores in Vault" do
      expect {
        post "/api/v1/credentials", params: valid_params, headers: headers
      }.to change(Credential, :count).by(1)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["name"]).to eq("my-service")
      expect(body).not_to have_key("password")
    end

    it "returns 422 for invalid credential type" do
      post "/api/v1/credentials",
           params: valid_params.merge(credential_type: "invalid_type"),
           headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 for duplicate name within project" do
      create(:credential, project: project, name: "existing-cred")
      post "/api/v1/credentials",
           params: valid_params.merge(name: "existing-cred"),
           headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /api/v1/credentials/:id" do
    let!(:cred) { create(:credential, project: project) }

    it "returns credential metadata" do
      get "/api/v1/credentials/#{cred.id}", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq(cred.id)
      expect(body["name"]).to eq(cred.name)
      expect(body).not_to have_key("password")
    end

    it "returns 404 for unknown credential" do
      get "/api/v1/credentials/#{SecureRandom.uuid}", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for credential from another project" do
      other      = create(:project)
      other_cred = create(:credential, project: other)
      get "/api/v1/credentials/#{other_cred.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT /api/v1/credentials/:id" do
    let!(:cred) { create(:credential, project: project) }

    it "updates credential metadata" do
      put "/api/v1/credentials/#{cred.id}",
          params: { service_url: "https://newurl.com/*" },
          headers: headers
      expect(response).to have_http_status(:ok)
      expect(cred.reload.service_url).to eq("https://newurl.com/*")
    end
  end

  describe "DELETE /api/v1/credentials/:id" do
    let!(:cred) { create(:credential, project: project, active: true) }

    it "deactivates the credential (does not hard-delete)" do
      delete "/api/v1/credentials/#{cred.id}", headers: headers
      expect(response).to have_http_status(:ok).or have_http_status(:no_content)
      # Should be deactivated, not destroyed
      expect(Credential.find_by(id: cred.id)).to be_present
    end
  end

  describe "POST /api/v1/credentials/:id/test" do
    let!(:cred) { create(:credential, project: project) }

    it "tests Vault connectivity" do
      post "/api/v1/credentials/#{cred.id}/test", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to have_key("success")
    end
  end
end
