require "rails_helper"

RSpec.describe Baseline, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:page) }
    it { is_expected.to belong_to(:browser_config) }
    it { is_expected.to have_many(:comparisons).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:branch) }
  end

  describe "scopes" do
    let(:project)        { create(:project) }
    let(:page)           { create(:page, project: project) }
    let(:browser_config) { create(:browser_config, project: project) }
    let!(:active_baseline)   { create(:baseline, page: page, browser_config: browser_config, active: true) }
    let!(:inactive_baseline) { create(:baseline, page: page, browser_config: browser_config, active: false) }
    let!(:feature_baseline)  { create(:baseline, :feature_branch, page: page, browser_config: browser_config, active: true) }

    it ".active returns only active baselines" do
      expect(Baseline.active).to include(active_baseline)
      expect(Baseline.active).not_to include(inactive_baseline)
    end

    it ".for_branch filters by branch" do
      expect(Baseline.for_branch("main")).to include(active_baseline, inactive_baseline)
      expect(Baseline.for_branch("main")).not_to include(feature_baseline)
    end

    it ".recent orders by created_at desc" do
      expect(Baseline.recent.first).to eq(feature_baseline)
    end
  end

  describe "#project" do
    it "returns project through page" do
      project  = create(:project)
      page     = create(:page, project: project)
      config   = create(:browser_config, project: project)
      baseline = create(:baseline, page: page, browser_config: config)
      expect(baseline.project).to eq(project)
    end
  end

  describe "#approve!" do
    it "marks baseline as active with approval info" do
      project  = create(:project)
      page     = create(:page, project: project)
      config   = create(:browser_config, project: project)
      baseline = create(:baseline, page: page, browser_config: config, active: false)

      baseline.approve!("admin@example.com")

      baseline.reload
      expect(baseline.active).to be true
      expect(baseline.approved_by).to eq("admin@example.com")
      expect(baseline.approved_at).to be_within(2.seconds).of(Time.current)
    end
  end

  describe "deactivate_previous callback" do
    it "deactivates previously active baselines for same page/config/branch" do
      project   = create(:project)
      page      = create(:page, project: project)
      config    = create(:browser_config, project: project)
      original  = create(:baseline, page: page, browser_config: config, branch: "main", active: true)

      # Creating a new active baseline should deactivate the original
      _new_baseline = create(:baseline, page: page, browser_config: config, branch: "main", active: true)

      expect(original.reload.active).to be false
    end

    it "does not affect baselines on other branches" do
      project       = create(:project)
      page          = create(:page, project: project)
      config        = create(:browser_config, project: project)
      main_baseline = create(:baseline, page: page, browser_config: config, branch: "main", active: true)

      _feature = create(:baseline, page: page, browser_config: config, branch: "feature", active: true)

      expect(main_baseline.reload.active).to be true
    end
  end
end
