require "rails_helper"

RSpec.describe Credential, type: :model do
  describe "associations" do
    it "belongs to a project" do
      project = create(:project)
      cred = create(:credential, project: project)
      expect(cred.project).to eq(project)
    end
  end

  describe "validations" do
    subject { build(:credential) }

    it { is_expected.to validate_presence_of(:name) }

    it "requires vault_path to be present (auto-set by callback)" do
      project = create(:project, platform_project_id: "proj_abc")
      cred = build(:credential, project: project, name: "test-svc")
      cred.valid?
      expect(cred.vault_path).to be_present
    end

    it { is_expected.to validate_inclusion_of(:credential_type).in_array(Credential::TYPES) }

    it "validates name uniqueness scoped to project_id" do
      project = create(:project)
      create(:credential, project: project, name: "github")
      dup = build(:credential, project: project, name: "github")
      expect(dup).not_to be_valid
      expect(dup.errors[:name]).to be_present
    end

    it "allows same name in different projects" do
      p1 = create(:project)
      p2 = create(:project)
      create(:credential, project: p1, name: "github")
      cred = build(:credential, project: p2, name: "github")
      expect(cred).to be_valid
    end

    it "rejects names with invalid characters" do
      cred = build(:credential, name: "my cred!")
      expect(cred).not_to be_valid
    end

    it "accepts names with dashes and underscores" do
      cred = build(:credential, name: "my-cred_v2")
      expect(cred).to be_valid
    end
  end

  describe "scopes" do
    let(:project) { create(:project) }
    let!(:active_cred)   { create(:credential, project: project, active: true, expires_at: nil) }
    let!(:inactive_cred) { create(:credential, :inactive, project: project) }
    let!(:expired_cred)  { create(:credential, :expired, project: project) }
    let!(:login_cred)    { create(:credential, project: project, credential_type: "login") }
    let!(:api_key_cred)  { create(:credential, :api_key, project: project) }

    it ".active returns active non-expired credentials" do
      expect(Credential.active).to include(active_cred, login_cred)
      expect(Credential.active).not_to include(inactive_cred, expired_cred)
    end

    it ".login_credentials returns only login type" do
      expect(Credential.login_credentials).to include(active_cred, login_cred)
      expect(Credential.login_credentials).not_to include(api_key_cred)
    end
  end

  describe "vault_path auto-generation" do
    it "generates vault_path from project and name" do
      project = create(:project, platform_project_id: "proj_123")
      cred    = create(:credential, project: project, name: "my-service")
      expect(cred.vault_path).to eq("/projects/proj_123/credentials/my-service")
    end

    it "does not overwrite existing vault_path" do
      project = create(:project)
      cred    = build(:credential, project: project, name: "svc", vault_path: "/custom/path")
      cred.valid?
      expect(cred.vault_path).to eq("/custom/path")
    end
  end

  describe "#expired?" do
    it "returns false when no expires_at" do
      cred = build(:credential, expires_at: nil)
      expect(cred.expired?).to be false
    end

    it "returns true when expires_at is in the past" do
      cred = build(:credential, :expired)
      expect(cred.expired?).to be true
    end

    it "returns false when expires_at is in the future" do
      cred = build(:credential, expires_at: 1.week.from_now)
      expect(cred.expired?).to be false
    end
  end

  describe "#matches_url?" do
    it "returns true when no service_url" do
      cred = build(:credential, service_url: nil)
      expect(cred.matches_url?("https://anything.com")).to be true
    end

    it "matches exact URL" do
      cred = build(:credential, service_url: "https://example.com")
      expect(cred.matches_url?("https://example.com")).to be true
    end

    it "matches wildcard patterns" do
      cred = build(:credential, service_url: "https://example.com/*")
      expect(cred.matches_url?("https://example.com/login")).to be true
    end

    it "does not match different domain" do
      cred = build(:credential, service_url: "https://example.com/*")
      expect(cred.matches_url?("https://other.com/login")).to be false
    end
  end

  describe "#login_selectors" do
    it "returns default selectors when no metadata" do
      cred = build(:credential, metadata: {})
      selectors = cred.login_selectors
      expect(selectors).to have_key(:username_field)
      expect(selectors).to have_key(:password_field)
      expect(selectors).to have_key(:submit_button)
    end

    it "returns custom selectors from metadata" do
      cred = build(:credential, :with_selectors)
      selectors = cred.login_selectors
      expect(selectors[:username_field]).to eq("#email")
      expect(selectors[:password_field]).to eq("#password")
    end
  end
end
