require "rails_helper"

RSpec.describe TestCase, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:project) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:steps) }

    context "steps format" do
      it "rejects steps that are not an array" do
        tc = build(:test_case, steps: "not an array")
        expect(tc).not_to be_valid
        expect(tc.errors[:steps]).to be_present
      end

      it "rejects steps with invalid action" do
        tc = build(:test_case, steps: [ { "action" => "fly" } ])
        expect(tc).not_to be_valid
        expect(tc.errors[:steps]).to be_present
      end

      it "rejects steps without action key" do
        tc = build(:test_case, steps: [ { "selector" => "#btn" } ])
        expect(tc).not_to be_valid
      end

      it "accepts valid steps" do
        tc = build(:test_case)
        expect(tc).to be_valid
      end

      it "accepts all valid action types" do
        TestCase::VALID_ACTIONS.each do |action|
          tc = build(:test_case, steps: [ { "action" => action } ])
          expect(tc).to be_valid, "Expected #{action} to be valid"
        end
      end
    end
  end

  describe "scopes" do
    let(:project) { create(:project) }
    let!(:enabled_case)  { create(:test_case, project: project, enabled: true, position: 5) }
    let!(:disabled_case) { create(:test_case, project: project, enabled: false, position: 1) }

    it ".enabled returns only enabled test cases" do
      expect(TestCase.enabled).to include(enabled_case)
      expect(TestCase.enabled).not_to include(disabled_case)
    end

    it ".ordered sorts by position" do
      expect(TestCase.ordered.first).to eq(disabled_case)
    end
  end

  describe "#step_count" do
    it "returns number of steps" do
      tc = build(:test_case, :with_login)
      expect(tc.step_count).to eq(5)
    end

    it "returns 0 when steps is nil" do
      tc = build(:test_case)
      allow(tc).to receive(:steps).and_return(nil)
      expect(tc.step_count).to eq(0)
    end
  end

  describe "#screenshot_steps" do
    it "returns only screenshot steps" do
      tc = build(:test_case)
      expect(tc.screenshot_steps.count).to eq(1)
      expect(tc.screenshot_steps.first["action"]).to eq("screenshot")
    end
  end

  describe "#navigation_steps" do
    it "returns only navigate steps" do
      tc = build(:test_case)
      expect(tc.navigation_steps.count).to eq(1)
      expect(tc.navigation_steps.first["action"]).to eq("navigate")
    end
  end
end
