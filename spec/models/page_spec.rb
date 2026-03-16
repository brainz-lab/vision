require "rails_helper"

RSpec.describe Page, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:project) }
    it { is_expected.to have_many(:baselines).dependent(:destroy) }
    it { is_expected.to have_many(:snapshots).dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:page) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:path) }
    it { is_expected.to validate_presence_of(:slug) }

    it "validates slug uniqueness scoped to project_id" do
      project = create(:project)
      create(:page, project: project, name: "Home", slug: "home")
      dup = build(:page, project: project, name: "Home 2", slug: "home")
      expect(dup).not_to be_valid
      expect(dup.errors[:slug]).to be_present
    end

    it "allows same slug in different projects" do
      p1 = create(:project)
      p2 = create(:project)
      create(:page, project: p1, slug: "home")
      page2 = build(:page, project: p2, slug: "home")
      expect(page2).to be_valid
    end
  end

  describe "slug generation" do
    it "auto-generates slug from name" do
      page = build(:page, name: "My Home Page", slug: nil)
      page.valid?
      expect(page.slug).to eq("my-home-page")
    end

    it "does not overwrite existing slug" do
      page = build(:page, name: "Home", slug: "custom-slug")
      page.valid?
      expect(page.slug).to eq("custom-slug")
    end
  end

  describe "scopes" do
    let(:project) { create(:project) }
    let!(:enabled_page)  { create(:page, project: project, enabled: true, position: 2) }
    let!(:disabled_page) { create(:page, project: project, enabled: false, position: 1) }

    it ".enabled returns only enabled pages" do
      expect(Page.enabled).to include(enabled_page)
      expect(Page.enabled).not_to include(disabled_page)
    end

    it ".ordered sorts by position" do
      expect(Page.ordered.to_a).to eq([ disabled_page, enabled_page ])
    end
  end

  describe "#full_url" do
    let(:project) { build(:project, base_url: "https://app.example.com") }
    let(:page)    { build(:page, project: project, path: "/dashboard") }

    it "constructs full URL from project base_url" do
      expect(page.full_url).to eq("https://app.example.com/dashboard")
    end

    it "accepts a custom base URL" do
      expect(page.full_url("https://staging.example.com")).to eq("https://staging.example.com/dashboard")
    end
  end

  describe "#current_baseline" do
    let(:project)        { create(:project) }
    let(:page)           { create(:page, project: project) }
    let(:browser_config) { create(:browser_config, project: project) }

    it "returns nil when no baseline exists" do
      expect(page.current_baseline(browser_config)).to be_nil
    end

    it "returns active baseline for the given config and branch" do
      baseline = create(:baseline, page: page, browser_config: browser_config, branch: "main", active: true)
      expect(page.current_baseline(browser_config, branch: "main")).to eq(baseline)
    end
  end

  describe "#effective_viewport" do
    let(:project) { build(:project) }

    it "falls back to project default when page has no viewport" do
      page = build(:page, project: project, viewport: nil)
      expect(page.effective_viewport).to eq(project.default_viewport)
    end

    it "returns page viewport when set" do
      page = build(:page, project: project, viewport: { "width" => 800, "height" => 600 })
      expect(page.effective_viewport).to eq({ "width" => 800, "height" => 600 })
    end
  end

  describe "#effective_hide_selectors" do
    let(:project) { build(:project, settings: { "api_key" => "vis_api_test", "ingest_key" => "vis_ingest_test", "hide_selectors" => [ ".ad" ] }) }
    let(:page)    { build(:page, project: project, hide_selectors: [ ".banner" ]) }

    it "merges page and project selectors" do
      expect(page.effective_hide_selectors).to include(".banner", ".ad")
    end
  end

  describe "#all_actions" do
    it "returns empty array when no actions set" do
      page = build(:page, actions: nil)
      expect(page.all_actions).to eq([])
    end

    it "returns actions array when set" do
      page = build(:page, :with_actions)
      expect(page.all_actions).not_to be_empty
    end
  end
end
