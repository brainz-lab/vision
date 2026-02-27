require "rails_helper"

RSpec.describe TestRun, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:project) }
    it { is_expected.to have_many(:snapshots).dependent(:destroy) }
    it { is_expected.to have_many(:comparisons).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[pending running passed failed error]) }
  end

  describe "scopes" do
    let(:project) { create(:project) }
    let!(:pending_run)  { create(:test_run, project: project, status: "pending") }
    let!(:running_run)  { create(:test_run, :running, project: project) }
    let!(:passed_run)   { create(:test_run, :passed,  project: project) }
    let!(:failed_run)   { create(:test_run, :failed,  project: project) }
    let!(:feature_run)  { create(:test_run, project: project, branch: "feature") }

    it ".completed returns finished runs" do
      expect(TestRun.completed).to include(passed_run, failed_run)
      expect(TestRun.completed).not_to include(pending_run, running_run)
    end

    it ".in_progress returns pending and running runs" do
      expect(TestRun.in_progress).to include(pending_run, running_run)
      expect(TestRun.in_progress).not_to include(passed_run)
    end

    it ".for_branch filters by branch" do
      expect(TestRun.for_branch("feature")).to include(feature_run)
      expect(TestRun.for_branch("feature")).not_to include(passed_run)
    end

    it ".recent orders by created_at desc" do
      expect(TestRun.recent.first).to eq(feature_run)
    end
  end

  describe "status predicates" do
    it "returns correct predicate for each status" do
      expect(build(:test_run, status: "pending").pending?).to be true
      expect(build(:test_run, :running).running?).to be true
      expect(build(:test_run, :passed).passed?).to be true
      expect(build(:test_run, :failed).failed?).to be true
    end

    it "#completed? returns true for passed/failed/error" do
      expect(build(:test_run, :passed).completed?).to be true
      expect(build(:test_run, :failed).completed?).to be true
      expect(build(:test_run, status: "error").completed?).to be true
      expect(build(:test_run, :running).completed?).to be false
    end
  end

  describe "#start!" do
    it "transitions to running and sets started_at" do
      run = create(:test_run)
      run.start!
      run.reload
      expect(run.status).to eq("running")
      expect(run.started_at).to be_within(2.seconds).of(Time.current)
    end
  end

  describe "#pass! and #fail!" do
    it "#pass! sets status to passed" do
      run = create(:test_run, :running)
      run.pass!
      expect(run.reload.status).to eq("passed")
    end

    it "#fail! sets status to failed" do
      run = create(:test_run, :running)
      run.fail!
      expect(run.reload.status).to eq("failed")
    end
  end

  describe "#complete!" do
    let(:project) { create(:project) }

    it "sets status to passed when no failures" do
      run = create(:test_run, :running, project: project, total_pages: 2, passed_count: 2, failed_count: 0, error_count: 0, notification_channels: [])
      run.complete!
      expect(run.reload.status).to eq("passed")
    end

    it "sets status to failed when failed_count > 0" do
      run = create(:test_run, :running, project: project, total_pages: 3, passed_count: 2, failed_count: 1, error_count: 0, notification_channels: [])
      run.complete!
      expect(run.reload.status).to eq("failed")
    end

    it "sets status to error when error_count > 0" do
      run = create(:test_run, :running, project: project, total_pages: 3, passed_count: 1, failed_count: 1, error_count: 1, notification_channels: [])
      run.complete!
      expect(run.reload.status).to eq("error")
    end
  end

  describe "#summary" do
    it "returns hash with expected keys" do
      run = build(:test_run, :passed)
      summary = run.summary
      expect(summary).to have_key(:total)
      expect(summary).to have_key(:passed)
      expect(summary).to have_key(:failed)
      expect(summary).to have_key(:pass_rate)
    end

    it "calculates pass_rate correctly" do
      run = build(:test_run, total_pages: 4, passed_count: 3, failed_count: 1, error_count: 0)
      expect(run.summary[:pass_rate]).to eq(75.0)
    end

    it "returns 0 pass_rate when no total_pages" do
      run = build(:test_run, total_pages: 0)
      expect(run.summary[:pass_rate]).to eq(0)
    end
  end

  describe "#progress" do
    it "calculates completion percentage" do
      run = build(:test_run, total_pages: 10, passed_count: 4, failed_count: 2, error_count: 1)
      expect(run.progress).to eq(70.0)
    end

    it "returns 0 when total_pages is 0" do
      run = build(:test_run, total_pages: 0)
      expect(run.progress).to eq(0)
    end
  end
end
