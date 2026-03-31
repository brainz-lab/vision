require "rails_helper"

RSpec.describe Mcp::Tools::VisionExtractFrames do
  let(:project) { create(:project) }
  let(:tool) { described_class.new(project) }
  let(:video_url) { "https://s3.example.com/recordings/test.webm" }

  describe "#call" do
    context "synchronous mode" do
      before do
        allow_any_instance_of(Media::VideoFrameExtractor).to receive(:extract).and_return({
          frames: [
            { timestamp_seconds: 0, timestamp_formatted: "00:00:00", data: "base64data", size_bytes: 1024 },
            { timestamp_seconds: 60, timestamp_formatted: "00:01:00", data: "base64data2", size_bytes: 1024 }
          ],
          video_duration: 120.0,
          video_resolution: { width: 1280, height: 720 },
          interval_seconds: 60,
          frame_count: 2
        })
      end

      it "extracts frames and returns metadata" do
        result = tool.call(video_url: video_url, interval_seconds: 60)

        expect(result[:success]).to be true
        expect(result[:data][:frame_count]).to eq(2)
        expect(result[:data][:video_duration]).to eq(120.0)
      end
    end

    context "asynchronous mode" do
      it "creates analysis and queues job" do
        expect {
          result = tool.call(video_url: video_url, async: true)
          expect(result[:success]).to be true
          expect(result[:data][:analysis_id]).to be_present
        }.to change(MediaAnalysis, :count).by(1)
      end
    end

    context "when video_url is missing" do
      it "returns error" do
        result = tool.call({})
        expect(result[:success]).to be false
      end
    end
  end
end
