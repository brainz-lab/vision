require "rails_helper"

RSpec.describe AiTask, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:project) }
    it { is_expected.to belong_to(:browser_session).optional }
    it { is_expected.to have_many(:steps).class_name("TaskStep").dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:ai_task) }

    it { is_expected.to validate_presence_of(:instruction) }
    it { is_expected.to validate_presence_of(:model) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:status).in_array(AiTask::STATUSES) }
    it { is_expected.to validate_inclusion_of(:triggered_by).in_array(AiTask::TRIGGERS).allow_nil }

    it "rejects max_steps <= 0" do
      expect(build(:ai_task, max_steps: 0)).not_to be_valid
    end

    it "rejects max_steps > 500" do
      expect(build(:ai_task, max_steps: 501)).not_to be_valid
    end

    it "rejects timeout_seconds > 3600" do
      expect(build(:ai_task, timeout_seconds: 3601)).not_to be_valid
    end
  end

  describe "scopes" do
    let(:project) { create(:project) }
    let!(:pending_task)   { create(:ai_task, project: project, status: "pending") }
    let!(:running_task)   { create(:ai_task, :running,   project: project) }
    let!(:completed_task) { create(:ai_task, :completed, project: project) }
    let!(:errored_task)   { create(:ai_task, :errored,   project: project) }
    let!(:mcp_task)       { create(:ai_task, :mcp,       project: project) }

    it ".active returns pending and running" do
      expect(AiTask.active).to include(pending_task, running_task)
      expect(AiTask.active).not_to include(completed_task)
    end

    it ".successful returns completed tasks" do
      expect(AiTask.successful).to include(completed_task)
      expect(AiTask.successful).not_to include(errored_task)
    end

    it ".failed returns stopped/timeout/error tasks" do
      expect(AiTask.failed).to include(errored_task)
      expect(AiTask.failed).not_to include(completed_task)
    end

    it ".by_trigger filters by trigger" do
      expect(AiTask.by_trigger("mcp")).to include(mcp_task)
      expect(AiTask.by_trigger("mcp")).not_to include(pending_task)
    end
  end

  describe "status predicates" do
    it "returns correct predicates" do
      expect(build(:ai_task, status: "pending").pending?).to be true
      expect(build(:ai_task, :running).running?).to be true
      expect(build(:ai_task, :completed).completed?).to be true
      expect(build(:ai_task, :stopped).stopped?).to be true
      expect(build(:ai_task, :timed_out).timed_out?).to be true
      expect(build(:ai_task, :errored).errored?).to be true
    end

    it "#finished? returns true for terminal states" do
      expect(build(:ai_task, :completed).finished?).to be true
      expect(build(:ai_task, :errored).finished?).to be true
      expect(build(:ai_task, status: "pending").finished?).to be false
    end

    it "#can_start? returns true only for pending" do
      expect(build(:ai_task, status: "pending").can_start?).to be true
      expect(build(:ai_task, :running).can_start?).to be false
    end

    it "#can_stop? returns true only for running" do
      expect(build(:ai_task, :running).can_stop?).to be true
      expect(build(:ai_task, status: "pending").can_stop?).to be false
    end
  end

  describe "state transitions" do
    let(:project) { create(:project) }

    describe "#start!" do
      it "transitions pending to running" do
        task = create(:ai_task, project: project, status: "pending")
        task.start!
        expect(task.reload.status).to eq("running")
        expect(task.started_at).to be_within(2.seconds).of(Time.current)
      end

      it "raises when not pending" do
        task = create(:ai_task, :running, project: project)
        expect { task.start! }.to raise_error(RuntimeError, /cannot be started/)
      end
    end

    describe "#complete!" do
      it "marks task as completed with result" do
        task = create(:ai_task, :running, project: project)
        task.complete!(result_text: "Done", data: { count: 5 })
        task.reload
        expect(task.status).to eq("completed")
        expect(task.result).to eq("Done")
        expect(task.completed_at).to be_within(2.seconds).of(Time.current)
      end
    end

    describe "#stop!" do
      it "marks task as stopped" do
        task = create(:ai_task, :running, project: project)
        task.stop!(reason: "Cancelled by user")
        expect(task.reload.status).to eq("stopped")
        expect(task.error_message).to eq("Cancelled by user")
      end
    end

    describe "#timeout!" do
      it "marks task as timed out" do
        task = create(:ai_task, :running, project: project, timeout_seconds: 30)
        task.timeout!
        expect(task.reload.status).to eq("timeout")
        expect(task.error_message).to include("30s")
      end
    end

    describe "#fail!" do
      it "marks task as error with message" do
        task = create(:ai_task, :running, project: project)
        task.fail!(RuntimeError.new("Network error"))
        expect(task.reload.status).to eq("error")
        expect(task.error_message).to eq("Network error")
      end
    end
  end

  describe "token tracking" do
    subject(:task) { build(:ai_task, :with_tokens) }

    it "#total_tokens returns sum of input and output tokens" do
      expect(task.total_tokens).to eq(2300)
    end

    it "returns 0 when tokens are nil" do
      task = build(:ai_task, total_input_tokens: nil, total_output_tokens: nil)
      expect(task.total_tokens).to eq(0)
    end
  end

  describe "#summary" do
    it "returns hash with required keys" do
      task = build(:ai_task, :completed)
      summary = task.summary
      expect(summary).to have_key(:id)
      expect(summary).to have_key(:status)
      expect(summary).to have_key(:instruction)
      expect(summary).to have_key(:steps_executed)
      expect(summary).to have_key(:total_tokens)
    end

    it "truncates instruction to 100 chars" do
      task = build(:ai_task, instruction: "A" * 150)
      expect(task.summary[:instruction].length).to be <= 100
    end
  end

  describe "#detail" do
    it "includes additional fields beyond summary" do
      task = build(:ai_task)
      detail = task.detail
      expect(detail).to have_key(:start_url)
      expect(detail).to have_key(:result)
      expect(detail).to have_key(:extracted_data)
    end
  end

  describe "defaults" do
    it "sets defaults on build" do
      task = build(:ai_task, status: nil, model: nil, max_steps: nil, timeout_seconds: nil)
      task.valid?
      expect(task.status).to eq("pending")
      expect(task.max_steps).to eq(100)
      expect(task.timeout_seconds).to eq(600)
      expect(task.capture_screenshots).to be true
    end
  end
end
