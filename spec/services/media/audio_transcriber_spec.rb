require "rails_helper"

RSpec.describe Media::AudioTranscriber do
  let(:audio_url) { "https://s3.example.com/recordings/test.webm" }
  let(:tmp_dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(tmp_dir) }

  describe "#transcribe" do
    context "when whisper.cpp is available" do
      let(:whisper_output) do
        <<~OUTPUT
          [00:00:00.000 --> 00:00:05.000] Buenos dias, vengo a revisar el medidor.
          [00:00:05.000 --> 00:00:10.000] Ingeniero, no hay forma de arreglar esto?
          [00:00:10.000 --> 00:00:15.000] Le puedo dar plata si no reporta nada.
        OUTPUT
      end

      before do
        allow_any_instance_of(described_class).to receive(:download_file).and_return("#{tmp_dir}/audio.wav")
        allow_any_instance_of(described_class).to receive(:convert_to_wav).and_return("#{tmp_dir}/audio.wav")
        allow_any_instance_of(described_class).to receive(:run_whisper).and_return(whisper_output)
      end

      it "returns parsed segments with timestamps" do
        service = described_class.new(audio_url, language: "es")
        result = service.transcribe

        expect(result[:segments]).to be_an(Array)
        expect(result[:segments].length).to eq(3)
        expect(result[:segments][0][:start]).to eq("00:00:00.000")
        expect(result[:segments][0][:end]).to eq("00:00:05.000")
        expect(result[:segments][0][:text]).to include("Buenos dias")
        expect(result[:full_text]).to include("Buenos dias")
        expect(result[:full_text]).to include("plata")
      end
    end

    context "when whisper.cpp is not available and fallback to API" do
      before do
        allow_any_instance_of(described_class).to receive(:download_file).and_return("#{tmp_dir}/audio.wav")
        allow_any_instance_of(described_class).to receive(:convert_to_wav).and_return("#{tmp_dir}/audio.wav")
        allow_any_instance_of(described_class).to receive(:whisper_available?).and_return(false)
        allow_any_instance_of(described_class).to receive(:transcribe_via_api).and_return({
          segments: [{ start: "00:00:00.000", end: "00:00:05.000", text: "Test transcription" }],
          full_text: "Test transcription"
        })
      end

      it "falls back to API transcription" do
        service = described_class.new(audio_url, language: "es")
        result = service.transcribe
        expect(result[:full_text]).to eq("Test transcription")
      end
    end

    context "when download fails" do
      before do
        allow_any_instance_of(described_class).to receive(:download_file).and_raise(StandardError, "Download failed")
      end

      it "raises an error" do
        service = described_class.new(audio_url)
        expect { service.transcribe }.to raise_error(StandardError, "Download failed")
      end
    end
  end

  describe "#parse_whisper_output" do
    it "parses VTT-style timestamp lines" do
      output = "[00:00:01.500 --> 00:00:03.200] Hello world\n[00:00:03.200 --> 00:00:05.000] Goodbye\n"
      service = described_class.new(audio_url)
      segments = service.send(:parse_whisper_output, output)

      expect(segments.length).to eq(2)
      expect(segments[0][:start]).to eq("00:00:01.500")
      expect(segments[0][:text]).to eq("Hello world")
    end
  end
end
