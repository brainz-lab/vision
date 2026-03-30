require "rails_helper"

RSpec.describe Media::VideoFrameExtractor do
  let(:video_url) { "https://s3.example.com/recordings/test.webm" }
  let(:tmp_dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(tmp_dir) }

  describe "#extract" do
    context "when video is valid" do
      let(:fake_movie) do
        double(
          "FFMPEG::Movie",
          valid?: true,
          duration: 180.0,
          width: 1280,
          height: 720
        )
      end

      before do
        allow_any_instance_of(described_class).to receive(:download_file).and_return("#{tmp_dir}/video.webm")
        allow(FFMPEG::Movie).to receive(:new).and_return(fake_movie)

        allow(fake_movie).to receive(:screenshot) do |output_path, _opts|
          FileUtils.touch(output_path)
        end
      end

      it "extracts frames at the specified interval" do
        service = described_class.new(video_url, interval_seconds: 60)
        result = service.extract

        expect(result[:frames]).to be_an(Array)
        expect(result[:frames].length).to eq(3)
        expect(result[:video_duration]).to eq(180.0)
      end

      it "includes timestamp for each frame" do
        service = described_class.new(video_url, interval_seconds: 60)
        result = service.extract

        expect(result[:frames][0][:timestamp_seconds]).to eq(0)
        expect(result[:frames][1][:timestamp_seconds]).to eq(60)
        expect(result[:frames][2][:timestamp_seconds]).to eq(120)
      end
    end

    context "when video is invalid" do
      before do
        allow_any_instance_of(described_class).to receive(:download_file).and_return("#{tmp_dir}/bad.webm")
        allow(FFMPEG::Movie).to receive(:new).and_return(double("movie", valid?: false))
      end

      it "raises an error" do
        service = described_class.new(video_url)
        expect { service.extract }.to raise_error(Media::VideoFrameExtractor::InvalidVideoError)
      end
    end
  end
end
