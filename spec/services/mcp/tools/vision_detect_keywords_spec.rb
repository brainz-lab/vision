require "rails_helper"

RSpec.describe Mcp::Tools::VisionDetectKeywords do
  let(:project) { create(:project) }
  let(:tool) { described_class.new(project) }

  let(:segments) do
    [
      { start: "00:00:00.000", end: "00:00:05.000", text: "Le puedo dar plata si no reporta." }
    ]
  end

  let(:keywords) { [ "plata", "no reporta", "arreglo" ] }

  describe "#call" do
    it "detects keywords in provided segments" do
      result = tool.call(segments: segments, keywords: keywords)

      expect(result[:success]).to be true
      expect(result[:data][:matches]).not_to be_empty
      expect(result[:data][:score]).to be > 0
    end

    it "accepts plain text instead of segments" do
      result = tool.call(text: "Le puedo dar plata si no reporta nada.", keywords: keywords)

      expect(result[:success]).to be true
      expect(result[:data][:matches]).not_to be_empty
    end

    it "returns error when keywords are missing" do
      result = tool.call(text: "some text")
      expect(result[:success]).to be false
      expect(result[:error]).to include("keywords")
    end
  end
end
