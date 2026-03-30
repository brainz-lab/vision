require "rails_helper"

RSpec.describe Media::VideoAnalyzer do
  let(:project) { create(:project, :with_ai) }
  let(:video_url) { "https://s3.example.com/recordings/test.webm" }
  let(:prompt) { "How many electrical meters are visible in this frame? List the serial numbers you can read." }

  let(:frames) do
    [
      { timestamp_seconds: 0, timestamp_formatted: "00:00:00", data: Base64.strict_encode64("fake_image_1") },
      { timestamp_seconds: 60, timestamp_formatted: "00:01:00", data: Base64.strict_encode64("fake_image_2") }
    ]
  end

  let(:fake_extractor_result) do
    {
      frames: frames,
      video_duration: 120.0,
      video_resolution: { width: 1280, height: 720 },
      interval_seconds: 60,
      frame_count: 2
    }
  end

  let(:fake_llm) do
    instance_double(LlmProviders::Anthropic).tap do |llm|
      allow(llm).to receive(:analyze_image).and_return({
        text: "I can see 2 electrical meters. Serial numbers: ABC-123 and DEF-456."
      })
      allow(llm).to receive(:complete).and_return({
        text: "Summary: 2 meters visible across all frames with serials ABC-123 and DEF-456."
      })
    end
  end

  before do
    allow(Media::VideoFrameExtractor).to receive(:new).and_return(
      double(extract: fake_extractor_result)
    )
    allow(LlmProviders::Factory).to receive(:for_project).and_return(fake_llm)
  end

  describe "#analyze" do
    it "extracts frames and analyzes each with Claude Vision" do
      service = described_class.new(project, video_url, prompt: prompt)
      result = service.analyze

      expect(result[:frame_analyses]).to be_an(Array)
      expect(result[:frame_analyses].length).to eq(2)
      expect(result[:frame_analyses][0][:analysis]).to include("2 electrical meters")
      expect(result[:frame_analyses][0][:timestamp]).to eq("00:00:00")
    end

    it "generates a consolidated summary" do
      service = described_class.new(project, video_url, prompt: prompt)
      result = service.analyze

      expect(result[:summary]).to be_a(String)
      expect(result[:summary]).to include("2 meters")
    end

    it "includes video metadata" do
      service = described_class.new(project, video_url, prompt: prompt)
      result = service.analyze

      expect(result[:video_duration]).to eq(120.0)
      expect(result[:frames_analyzed]).to eq(2)
    end
  end
end
