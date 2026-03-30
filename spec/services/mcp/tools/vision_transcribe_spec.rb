require "rails_helper"

RSpec.describe Mcp::Tools::VisionTranscribe do
  let(:project) { create(:project) }
  let(:tool) { described_class.new(project) }
  let(:audio_url) { "https://s3.example.com/recordings/test.webm" }

  describe "#call" do
    context "synchronous mode" do
      before do
        allow_any_instance_of(Media::AudioTranscriber).to receive(:transcribe).and_return({
          segments: [{ start: "00:00:00.000", end: "00:00:05.000", text: "Hola mundo" }],
          full_text: "Hola mundo",
          language: "es",
          engine: "whisper.cpp"
        })
      end

      it "transcribes audio and returns result" do
        result = tool.call(audio_url: audio_url, language: "es")

        expect(result[:success]).to be true
        expect(result[:data][:full_text]).to eq("Hola mundo")
        expect(result[:data][:segments].length).to eq(1)
      end
    end

    context "asynchronous mode" do
      it "creates a MediaAnalysis record and queues job" do
        expect {
          result = tool.call(audio_url: audio_url, async: true)
          expect(result[:success]).to be true
          expect(result[:data][:analysis_id]).to be_present
          expect(result[:data][:status]).to eq("pending")
        }.to change(MediaAnalysis, :count).by(1)
      end
    end

    context "when audio_url is missing" do
      it "returns an error" do
        result = tool.call({})
        expect(result[:success]).to be false
        expect(result[:error]).to include("audio_url")
      end
    end
  end
end
