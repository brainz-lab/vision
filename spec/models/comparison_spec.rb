require "rails_helper"

RSpec.describe Comparison, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:baseline) }
    it { is_expected.to belong_to(:snapshot) }
    it { is_expected.to belong_to(:test_run).optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[pending passed failed error]) }
  end

  describe "scopes" do
    let(:project)  { create(:project) }
    let(:page)     { create(:page, project: project) }
    let(:config)   { create(:browser_config, project: project) }
    let(:baseline) { create(:baseline, page: page, browser_config: config) }
    let!(:passed_comp)   { create(:comparison, baseline: baseline, snapshot: build_snapshot(page, config), status: "passed", review_status: nil) }
    let!(:failed_comp)   { create(:comparison, :failed, baseline: baseline, snapshot: build_snapshot(page, config)) }
    let!(:approved_comp) { create(:comparison, :approved, baseline: baseline, snapshot: build_snapshot(page, config)) }
    let!(:rejected_comp) { create(:comparison, :rejected, baseline: baseline, snapshot: build_snapshot(page, config)) }

    def build_snapshot(page, config)
      create(:snapshot, page: page, browser_config: config)
    end

    it ".passed returns passed comparisons" do
      expect(Comparison.passed).to include(passed_comp)
      expect(Comparison.passed).not_to include(failed_comp)
    end

    it ".failed returns failed comparisons" do
      expect(Comparison.failed).to include(failed_comp)
      expect(Comparison.failed).not_to include(passed_comp)
    end

    it ".pending_review returns comparisons with pending review_status" do
      expect(Comparison.pending_review).to include(failed_comp)
    end

    it ".approved returns approved comparisons" do
      expect(Comparison.approved).to include(approved_comp)
    end

    it ".rejected returns rejected comparisons" do
      expect(Comparison.rejected).to include(rejected_comp)
    end
  end

  describe "status predicates" do
    it "#passed? returns true for passed status" do
      comp = build(:comparison, status: "passed")
      expect(comp.passed?).to be true
      expect(comp.failed?).to be false
    end

    it "#failed? returns true for failed status" do
      comp = build(:comparison, :failed)
      expect(comp.failed?).to be true
      expect(comp.passed?).to be false
    end

    it "#needs_review? is true for failed pending review" do
      comp = build(:comparison, :failed)
      expect(comp.needs_review?).to be true
    end

    it "#needs_review? is false when not pending" do
      comp = build(:comparison, :approved)
      expect(comp.needs_review?).to be false
    end
  end

  describe "#reject!" do
    it "sets review_status to rejected with notes and reviewer" do
      project  = create(:project)
      page     = create(:page, project: project)
      config   = create(:browser_config, project: project)
      baseline = create(:baseline, page: page, browser_config: config)
      snapshot = create(:snapshot, page: page, browser_config: config)
      comp     = create(:comparison, :failed, baseline: baseline, snapshot: snapshot)

      comp.reject!("reviewer@example.com", notes: "Looks wrong")

      comp.reload
      expect(comp.review_status).to eq("rejected")
      expect(comp.reviewed_by).to eq("reviewer@example.com")
      expect(comp.review_notes).to eq("Looks wrong")
    end
  end

  describe "#diff_summary" do
    it "returns nil when no diff_percentage" do
      comp = build(:comparison, diff_percentage: nil)
      expect(comp.diff_summary).to be_nil
    end

    it "returns passing summary for passed comparison" do
      comp = build(:comparison, status: "passed", diff_percentage: 0.5)
      expect(comp.diff_summary).to include("Passed")
      expect(comp.diff_summary).to include("0.5%")
    end

    it "returns failing summary for failed comparison" do
      comp = build(:comparison, :failed)
      expect(comp.diff_summary).to include("Failed")
    end
  end

  describe "#project and #page shortcuts" do
    it "#project traverses snapshot -> page -> project" do
      project  = create(:project)
      page     = create(:page, project: project)
      config   = create(:browser_config, project: project)
      baseline = create(:baseline, page: page, browser_config: config)
      snapshot = create(:snapshot, page: page, browser_config: config)
      comp     = create(:comparison, baseline: baseline, snapshot: snapshot)
      expect(comp.project).to eq(project)
      expect(comp.page).to eq(page)
    end
  end
end
