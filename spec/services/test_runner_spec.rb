require "rails_helper"

RSpec.describe TestRunner do
  let(:project)        { create(:project) }
  let(:browser_config) { create(:browser_config, project: project, enabled: true) }
  let!(:page1)         { create(:page, project: project, enabled: true) }
  let!(:page2)         { create(:page, project: project, enabled: true) }

  before do
    browser_config # ensure it's created
    allow(CaptureScreenshotJob).to receive(:perform_later)
  end

  describe "#run!" do
    let(:test_run) do
      create(:test_run, project: project, status: "pending", branch: "main", environment: "staging", triggered_by: "api")
    end

    it "starts the test run" do
      TestRunner.new(test_run).run!
      expect(test_run.reload.status).to eq("running")
    end

    it "sets total_pages based on pages × configs" do
      TestRunner.new(test_run).run!
      expect(test_run.reload.total_pages).to eq(2) # 2 pages × 1 config
    end

    it "creates snapshots for each page/browser_config combination" do
      expect {
        TestRunner.new(test_run).run!
      }.to change(Snapshot, :count).by(2)
    end

    it "queues CaptureScreenshotJob for each snapshot" do
      TestRunner.new(test_run).run!
      expect(CaptureScreenshotJob).to have_received(:perform_later).twice
    end

    it "returns the test_run" do
      result = TestRunner.new(test_run).run!
      expect(result).to eq(test_run)
    end

    context "with multiple browser configs" do
      let!(:second_config) { create(:browser_config, :mobile, project: project, enabled: true) }

      it "creates snapshots for every page/config combination" do
        expect {
          TestRunner.new(test_run).run!
        }.to change(Snapshot, :count).by(4) # 2 pages × 2 configs
      end
    end

    context "with disabled pages" do
      before { page2.update!(enabled: false) }

      it "only captures enabled pages" do
        expect {
          TestRunner.new(test_run).run!
        }.to change(Snapshot, :count).by(1) # only page1
      end
    end

    context "with disabled browser configs" do
      before { browser_config.update!(enabled: false) }

      it "creates no snapshots when all configs are disabled" do
        expect {
          TestRunner.new(test_run).run!
        }.not_to change(Snapshot, :count)
      end
    end
  end

  describe ".run_for_project!" do
    it "creates a test run and starts it" do
      expect {
        TestRunner.run_for_project!(project, branch: "feature/test", environment: "staging")
      }.to change(TestRun, :count).by(1)

      run = TestRun.order(:created_at).last
      expect(run.status).to eq("running")
      expect(run.branch).to eq("feature/test")
    end

    it "defaults branch to main and environment to staging" do
      TestRunner.run_for_project!(project)
      run = TestRun.order(:created_at).last
      expect(run.branch).to eq("main")
      expect(run.environment).to eq("staging")
    end

    it "passes PR info when provided" do
      TestRunner.run_for_project!(project, pr_number: 42, pr_url: "https://github.com/org/repo/pull/42")
      run = TestRun.order(:created_at).last
      expect(run.pr_number).to eq(42)
    end
  end
end
