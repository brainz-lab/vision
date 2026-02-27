require "rails_helper"

RSpec.describe BrowserConfig, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:project) }
    it { is_expected.to have_many(:baselines).dependent(:destroy) }
    it { is_expected.to have_many(:snapshots).dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:browser_config) }

    it { is_expected.to validate_presence_of(:browser) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:width) }
    it { is_expected.to validate_presence_of(:height) }
    it { is_expected.to validate_inclusion_of(:browser).in_array(%w[chromium firefox webkit]) }

    it "rejects width <= 0" do
      config = build(:browser_config, width: 0)
      expect(config).not_to be_valid
    end

    it "rejects height <= 0" do
      config = build(:browser_config, height: -1)
      expect(config).not_to be_valid
    end
  end

  describe "scopes" do
    let(:project) { create(:project) }
    let!(:enabled_config)  { create(:browser_config, project: project, enabled: true) }
    let!(:disabled_config) { create(:browser_config, project: project, enabled: false) }

    it ".enabled returns only enabled configs" do
      expect(BrowserConfig.enabled).to include(enabled_config)
      expect(BrowserConfig.enabled).not_to include(disabled_config)
    end
  end

  describe "#to_viewport_config" do
    subject(:config) { build(:browser_config, width: 1280, height: 720, device_scale_factor: 2.0) }

    it "returns viewport config hash" do
      result = config.to_viewport_config
      expect(result[:width]).to eq(1280)
      expect(result[:height]).to eq(720)
      expect(result[:device_scale_factor]).to eq(2.0)
      expect(result[:is_mobile]).to be false
      expect(result[:has_touch]).to be false
    end

    it "includes user_agent when set" do
      config.user_agent = "Custom UA"
      expect(config.to_viewport_config[:user_agent]).to eq("Custom UA")
    end

    it "omits user_agent when blank" do
      config.user_agent = nil
      expect(config.to_viewport_config).not_to have_key(:user_agent)
    end
  end

  describe "#display_name" do
    it "formats name with resolution" do
      config = build(:browser_config, name: "Chrome Desktop", width: 1280, height: 720)
      expect(config.display_name).to eq("Chrome Desktop (1280x720)")
    end
  end

  describe "mobile config" do
    subject(:config) { build(:browser_config, :mobile) }

    it "sets is_mobile and has_touch" do
      expect(config.to_viewport_config[:is_mobile]).to be true
      expect(config.to_viewport_config[:has_touch]).to be true
    end
  end
end
