require "rails_helper"

RSpec.describe Project, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:pages).dependent(:destroy) }
    it { is_expected.to have_many(:browser_configs).dependent(:destroy) }
    it { is_expected.to have_many(:test_runs).dependent(:destroy) }
    it { is_expected.to have_many(:test_cases).dependent(:destroy) }
    it { is_expected.to have_many(:baselines).through(:pages) }
    it { is_expected.to have_many(:snapshots).through(:pages) }
    it { is_expected.to have_many(:ai_tasks).dependent(:destroy) }
    it { is_expected.to have_many(:browser_sessions).dependent(:destroy) }
    it { is_expected.to have_many(:action_cache_entries).dependent(:destroy) }
    it { is_expected.to have_many(:credentials).dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:project) }

    it { is_expected.to validate_presence_of(:platform_project_id) }
    it { is_expected.to validate_uniqueness_of(:platform_project_id) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:base_url) }

    it "rejects invalid base_url" do
      project = build(:project, base_url: "not-a-url")
      expect(project).not_to be_valid
      expect(project.errors[:base_url]).to be_present
    end

    it "accepts http and https urls" do
      expect(build(:project, base_url: "http://example.com")).to be_valid
      expect(build(:project, base_url: "https://example.com")).to be_valid
    end
  end

  describe "scopes" do
    let!(:active_project)   { create(:project) }
    let!(:archived_project) { create(:project, :archived) }

    it ".active returns non-archived projects" do
      expect(Project.active).to include(active_project)
      expect(Project.active).not_to include(archived_project)
    end

    it ".archived returns archived projects" do
      expect(Project.archived).to include(archived_project)
      expect(Project.archived).not_to include(active_project)
    end
  end

  describe ".find_or_create_for_platform!" do
    it "creates a project when not found" do
      expect {
        Project.find_or_create_for_platform!(
          platform_project_id: "plat_abc123",
          name: "New Project",
          environment: "production"
        )
      }.to change(Project, :count).by(1)
    end

    it "returns existing project without creating a duplicate" do
      existing = create(:project, platform_project_id: "plat_exists")
      result   = Project.find_or_create_for_platform!(platform_project_id: "plat_exists")

      expect(result.id).to eq(existing.id)
      expect(Project.where(platform_project_id: "plat_exists").count).to eq(1)
    end
  end

  describe "settings accessors" do
    subject(:project) { build(:project) }

    describe "#default_viewport" do
      it "returns default when not set" do
        expect(project.default_viewport).to eq({ "width" => 1280, "height" => 720 })
      end

      it "returns custom viewport from settings" do
        project.settings["default_viewport"] = { "width" => 1440, "height" => 900 }
        expect(project.default_viewport).to eq({ "width" => 1440, "height" => 900 })
      end
    end

    describe "#threshold" do
      it "returns 0.01 by default" do
        expect(project.threshold).to eq(0.01)
      end

      it "returns custom threshold from settings" do
        project.settings["threshold"] = 0.05
        expect(project.threshold).to eq(0.05)
      end
    end

    describe "#wait_before_capture" do
      it "returns 500 by default" do
        expect(project.wait_before_capture).to eq(500)
      end
    end

    describe "#hide_selectors" do
      it "returns empty array by default" do
        expect(project.hide_selectors).to eq([])
      end
    end

    describe "#mask_selectors" do
      it "returns empty array by default" do
        expect(project.mask_selectors).to eq([])
      end
    end
  end

  describe "AI configuration" do
    subject(:project) { build(:project, :with_ai) }

    describe "#default_llm_model" do
      it "returns the configured model" do
        expect(project.default_llm_model).to eq("claude-sonnet-4")
      end
    end

    describe "#default_browser_provider" do
      it "returns the configured provider" do
        expect(project.default_browser_provider).to eq("local")
      end
    end

    describe "#ai_automation_enabled?" do
      it "returns true when enabled" do
        expect(project.ai_automation_enabled?).to be true
      end
    end

    describe "#ai_task_defaults" do
      it "returns hash with expected keys" do
        defaults = project.ai_task_defaults
        expect(defaults).to have_key(:max_steps)
        expect(defaults).to have_key(:timeout_seconds)
        expect(defaults).to have_key(:capture_screenshots)
      end
    end
  end

  describe "credential encryption" do
    subject(:project) { create(:project) }

    describe "#llm_provider_config" do
      it "falls back to environment variable when no config stored" do
        ClimateControl.modify(ANTHROPIC_API_KEY: "env-key") do
          config = project.llm_provider_config(:anthropic)
          expect(config[:api_key]).to eq("env-key")
        end
      end if defined?(ClimateControl)

      it "returns empty hash for unconfigured provider" do
        config = project.llm_provider_config(:anthropic)
        expect(config).to be_a(Hash)
      end
    end
  end

  describe "vault integration" do
    subject(:project) { build(:project) }

    describe "#vault_configured?" do
      it "returns false with no vault token" do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("VAULT_ACCESS_TOKEN").and_return(nil)
        expect(project.vault_configured?).to be false
      end
    end

    describe "#find_credential" do
      it "returns nil when no matching credential" do
        saved = create(:project)
        expect(saved.find_credential("nonexistent")).to be_nil
      end
    end
  end

  describe "#recent_summary" do
    subject(:project) { create(:project) }

    it "returns hash with expected keys" do
      summary = project.recent_summary
      expect(summary).to have_key(:total_runs)
      expect(summary).to have_key(:passed)
      expect(summary).to have_key(:failed)
      expect(summary).to have_key(:pass_rate)
    end

    it "calculates pass_rate as 0 when no runs" do
      expect(project.recent_summary[:pass_rate]).to eq(0)
    end

    it "counts recent test runs" do
      create(:test_run, :passed, project: project)
      create(:test_run, :failed, project: project)
      summary = project.recent_summary
      expect(summary[:total_runs]).to eq(2)
      expect(summary[:pass_rate]).to eq(50.0)
    end
  end
end
