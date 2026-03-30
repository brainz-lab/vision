require "rails_helper"

RSpec.describe MediaAnalysisJob do
  let(:project) { create(:project, :with_ai) }

  describe "#perform" do
    context "transcription" do
      let(:analysis) { create(:media_analysis, :transcription, project: project) }

      before do
        allow_any_instance_of(Media::AudioTranscriber).to receive(:transcribe).and_return({
          segments: [{ start: "00:00:00.000", end: "00:00:05.000", text: "Hello" }],
          full_text: "Hello",
          language: "es",
          engine: "whisper.cpp"
        })
      end

      it "runs AudioTranscriber and completes the analysis" do
        described_class.new.perform(analysis.id)

        analysis.reload
        expect(analysis.status).to eq("completed")
        expect(analysis.result["full_text"]).to eq("Hello")
      end
    end

    context "keyword detection" do
      let(:analysis) do
        create(:media_analysis, :keyword_detection, project: project,
               parameters: { "keywords" => ["plata"], "text" => "Le doy plata" })
      end

      it "runs KeywordDetector and completes the analysis" do
        described_class.new.perform(analysis.id)

        analysis.reload
        expect(analysis.status).to eq("completed")
        expect(analysis.result["score"]).to be > 0
      end
    end

    context "when analysis is already finished" do
      let(:analysis) { create(:media_analysis, :completed, project: project) }

      it "returns early without processing" do
        expect_any_instance_of(Media::AudioTranscriber).not_to receive(:transcribe)
        described_class.new.perform(analysis.id)
      end
    end

    context "when processing fails" do
      let(:analysis) { create(:media_analysis, :transcription, project: project) }

      before do
        allow_any_instance_of(Media::AudioTranscriber).to receive(:transcribe)
          .and_raise(StandardError, "whisper crashed")
      end

      it "marks the analysis as error" do
        expect { described_class.new.perform(analysis.id) }.to raise_error(StandardError)
        expect(analysis.reload.status).to eq("error")
      end
    end
  end
end
