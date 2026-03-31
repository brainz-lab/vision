require "rails_helper"

RSpec.describe TaskStep, type: :model do
  describe "associations" do
    it "belongs to an ai_task" do
      project = create(:project)
      task = create(:ai_task, project: project)
      step = create(:task_step, ai_task: task)
      expect(step.ai_task).to eq(task)
    end
  end

  describe "validations" do
    subject do
      task = create(:ai_task, project: create(:project))
      build(:task_step, ai_task: task)
    end

    it { is_expected.to validate_presence_of(:action) }
    it { is_expected.to validate_inclusion_of(:action).in_array(TaskStep::ACTIONS) }

    it "rejects position < 0" do
      task = create(:ai_task, project: create(:project))
      step = build(:task_step, ai_task: task, position: -1)
      expect(step).not_to be_valid
    end
  end

  describe "scopes" do
    let(:task) { create(:ai_task, project: create(:project)) }
    let!(:success_step) { create(:task_step, ai_task: task, action: "click", success: true, position: 0) }
    let!(:failed_step)  { create(:task_step, :failed, ai_task: task, position: 1) }
    let!(:nav_step)     { create(:task_step, :navigate, ai_task: task, position: 2) }

    it ".ordered returns steps by position" do
      expect(TaskStep.ordered.to_a).to eq([ success_step, failed_step, nav_step ])
    end

    it ".successful returns steps where success is true" do
      expect(TaskStep.successful).to include(success_step)
      expect(TaskStep.successful).not_to include(failed_step)
    end

    it ".failed returns steps where success is false" do
      expect(TaskStep.failed).to include(failed_step)
      expect(TaskStep.failed).not_to include(success_step)
    end

    it ".by_action filters by action type" do
      expect(TaskStep.by_action("navigate")).to include(nav_step)
      expect(TaskStep.by_action("navigate")).not_to include(success_step)
    end
  end

  describe "auto-position" do
    it "assigns next position automatically" do
      project = create(:project)
      task    = create(:ai_task, project: project)
      step1   = create(:task_step, ai_task: task, position: nil)
      step2   = create(:task_step, ai_task: task, position: nil)
      expect(step1.position).to eq(0)
      expect(step2.position).to eq(1)
    end
  end

  describe "action predicates" do
    TaskStep::ACTIONS.each do |action_type|
      it "#{action_type}? returns true when action is #{action_type}" do
        task = build(:ai_task)
        step = build(:task_step, ai_task: task, action: action_type)
        expect(step.public_send("#{action_type}?")).to be true
      end
    end
  end

  describe "#action_summary" do
    let(:task) { build(:ai_task) }

    it "describes click action" do
      step = build(:task_step, ai_task: task, action: "click", selector: "#btn")
      expect(step.action_summary).to include("Click")
    end

    it "describes navigate action" do
      step = build(:task_step, :navigate, ai_task: task)
      expect(step.action_summary).to include("Navigate")
    end

    it "describes type action" do
      step = build(:task_step, :type, ai_task: task)
      expect(step.action_summary).to include("Type")
    end

    it "describes done action" do
      step = build(:task_step, :done, ai_task: task)
      expect(step.action_summary).to include("Task complete")
    end
  end

  describe "#total_tokens" do
    it "returns sum of input and output tokens" do
      task = build(:ai_task)
      step = build(:task_step, :with_tokens, ai_task: task)
      expect(step.total_tokens).to eq(250)
    end

    it "returns 0 when tokens are nil" do
      task = build(:ai_task)
      step = build(:task_step, ai_task: task, input_tokens: nil, output_tokens: nil)
      expect(step.total_tokens).to eq(0)
    end
  end

  describe "#detail" do
    it "returns complete step information" do
      task   = create(:ai_task, project: create(:project))
      step   = create(:task_step, ai_task: task)
      detail = step.detail
      expect(detail).to have_key(:position)
      expect(detail).to have_key(:action)
      expect(detail).to have_key(:success)
      expect(detail).to have_key(:total_tokens)
    end
  end
end
