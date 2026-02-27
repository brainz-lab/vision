require "rails_helper"

RSpec.describe Snapshot, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:page) }
    it { is_expected.to belong_to(:browser_config) }
    it { is_expected.to belong_to(:test_run).optional }
    it { is_expected.to have_one(:comparison).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[pending captured comparing compared error]) }
  end

  describe "scopes" do
    let(:project)        { create(:project) }
    let(:page)           { create(:page, project: project) }
    let(:config)         { create(:browser_config, project: project) }
    let!(:pending_snap)  { create(:snapshot, page: page, browser_config: config, status: "pending") }
    let!(:captured_snap) { create(:snapshot, :captured, page: page, browser_config: config) }
    let!(:feature_snap)  { create(:snapshot, page: page, browser_config: config, branch: "feature") }

    it ".captured returns only captured snapshots" do
      expect(Snapshot.captured).to include(captured_snap)
      expect(Snapshot.captured).not_to include(pending_snap)
    end

    it ".for_branch filters by branch" do
      expect(Snapshot.for_branch("feature")).to include(feature_snap)
      expect(Snapshot.for_branch("feature")).not_to include(pending_snap)
    end
  end

  describe "#project" do
    it "returns project through page" do
      project  = create(:project)
      page     = create(:page, project: project)
      config   = create(:browser_config, project: project)
      snapshot = create(:snapshot, page: page, browser_config: config)
      expect(snapshot.project).to eq(project)
    end
  end

  describe "state transitions" do
    let(:project)  { create(:project) }
    let(:page)     { create(:page, project: project) }
    let(:config)   { create(:browser_config, project: project) }
    let(:snapshot) { create(:snapshot, page: page, browser_config: config) }

    describe "#mark_captured!" do
      it "sets status to captured with timestamp" do
        snapshot.mark_captured!(duration_ms: 1200)
        snapshot.reload
        expect(snapshot.status).to eq("captured")
        expect(snapshot.captured_at).to be_within(2.seconds).of(Time.current)
        expect(snapshot.capture_duration_ms).to eq(1200)
      end
    end

    describe "#mark_comparing!" do
      it "sets status to comparing" do
        snapshot.mark_comparing!
        expect(snapshot.reload.status).to eq("comparing")
      end
    end

    describe "#mark_compared!" do
      it "sets status to compared" do
        snapshot.mark_compared!
        expect(snapshot.reload.status).to eq("compared")
      end
    end

    describe "#mark_error!" do
      it "sets status to error with message in metadata" do
        snapshot.mark_error!("Playwright timeout")
        snapshot.reload
        expect(snapshot.status).to eq("error")
        expect(snapshot.metadata["error"]).to eq("Playwright timeout")
      end
    end
  end

  describe "#compare_to_baseline!" do
    let(:project)  { create(:project) }
    let(:page)     { create(:page, project: project) }
    let(:config)   { create(:browser_config, project: project) }
    let(:snapshot) { create(:snapshot, page: page, browser_config: config) }

    it "returns nil when no baseline exists" do
      expect(snapshot.compare_to_baseline!).to be_nil
    end
  end
end
