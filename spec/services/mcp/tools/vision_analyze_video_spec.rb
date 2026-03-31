require "rails_helper"

RSpec.describe Mcp::Tools::VisionAnalyzeVideo do
  let(:project) { create(:project, :with_ai) }
  let(:tool) { described_class.new(project) }
  let(:video_url) { "https://s3.example.com/recordings/inspection.webm" }
  let(:prompt) { "How many electrical meters are visible? List serial numbers." }

  describe "#call" do
    context "synchronous mode" do
      before do
        allow_any_instance_of(Media::VideoAnalyzer).to receive(:analyze).and_return({
          frame_analyses: [
            { timestamp: "00:00:00", timestamp_seconds: 0, analysis: "2 meters visible: ABC-123, DEF-456" }
          ],
          summary: "2 meters found across all frames.",
          video_duration: 60.0,
          video_resolution: { width: 1280, height: 720 },
          frames_analyzed: 1,
          interval_seconds: 60,
          model: "claude-sonnet-4"
        })
      end

      it "analyzes video and returns frame analyses with summary" do
        result = tool.call(video_url: video_url, prompt: prompt)

        expect(result[:success]).to be true
        expect(result[:data][:frame_analyses].length).to eq(1)
        expect(result[:data][:summary]).to include("2 meters")
        expect(result[:data][:frames_analyzed]).to eq(1)
      end
    end

    context "asynchronous mode" do
      it "creates analysis and queues job" do
        expect {
          result = tool.call(video_url: video_url, prompt: prompt, async: true)
          expect(result[:success]).to be true
          expect(result[:data][:analysis_id]).to be_present
        }.to change(MediaAnalysis, :count).by(1)
      end
    end

    context "when required params missing" do
      it "returns error when video_url missing" do
        result = tool.call(prompt: prompt)
        expect(result[:success]).to be false
      end

      it "returns error when prompt missing" do
        result = tool.call(video_url: video_url)
        expect(result[:success]).to be false
      end
    end
  end
end
