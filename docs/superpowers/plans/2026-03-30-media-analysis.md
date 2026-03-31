# Vision Media Analysis Extension — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend Vision with audio transcription (whisper.cpp), video frame extraction (FFmpeg), keyword detection, and video analysis capabilities exposed as 4 new MCP tools.

**Architecture:** New `Media::` service namespace under `app/services/media/` with 4 focused services. Each service is independently testable and accessed via MCP tools registered in `Mcp::Server`. Audio uses whisper.cpp CLI (MIT, local). Video uses FFmpeg CLI via `streamio-ffmpeg` gem. Image analysis reuses the existing `LlmProviders::Factory` + `analyze_image`. A new `MediaAnalysis` model tracks async media processing jobs.

**Tech Stack:** Rails 8, whisper.cpp (MIT), FFmpeg + streamio-ffmpeg gem, Claude Vision API (existing), S3/MinIO (existing Active Storage), Solid Queue (existing)

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `app/models/media_analysis.rb` | AR model tracking media analysis requests (status, type, input, output) |
| `db/migrate/xxx_create_media_analyses.rb` | Migration for media_analyses table |
| `spec/factories/media_analyses.rb` | Factory for tests |
| `app/services/media/audio_transcriber.rb` | Runs whisper.cpp on audio file, returns timestamped segments |
| `app/services/media/keyword_detector.rb` | Scans text for keywords, returns matches with context and score |
| `app/services/media/video_frame_extractor.rb` | Runs FFmpeg to extract frames at interval, uploads to S3 |
| `app/services/media/video_analyzer.rb` | Sends frames to Claude Vision via LLM provider, returns analysis |
| `app/jobs/media_analysis_job.rb` | Async job dispatching to the correct Media service |
| `app/services/mcp/tools/vision_transcribe.rb` | MCP tool for audio transcription |
| `app/services/mcp/tools/vision_detect_keywords.rb` | MCP tool for keyword detection |
| `app/services/mcp/tools/vision_extract_frames.rb` | MCP tool for video frame extraction |
| `app/services/mcp/tools/vision_analyze_video.rb` | MCP tool for video analysis |
| `spec/services/media/audio_transcriber_spec.rb` | Tests for AudioTranscriber |
| `spec/services/media/keyword_detector_spec.rb` | Tests for KeywordDetector |
| `spec/services/media/video_frame_extractor_spec.rb` | Tests for VideoFrameExtractor |
| `spec/services/media/video_analyzer_spec.rb` | Tests for VideoAnalyzer |
| `spec/jobs/media_analysis_job_spec.rb` | Tests for the job |
| `spec/services/mcp/tools/vision_transcribe_spec.rb` | Tests for MCP tool |
| `spec/services/mcp/tools/vision_detect_keywords_spec.rb` | Tests for MCP tool |
| `spec/services/mcp/tools/vision_extract_frames_spec.rb` | Tests for MCP tool |
| `spec/services/mcp/tools/vision_analyze_video_spec.rb` | Tests for MCP tool |

### Modified Files

| File | Change |
|------|--------|
| `Gemfile` | Add `streamio-ffmpeg` gem |
| `app/services/mcp/server.rb` | Register 4 new tools in TOOLS hash |
| `app/models/project.rb` | Add `has_many :media_analyses` association |

---

## Task 1: Add streamio-ffmpeg gem

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Add gem to Gemfile**

Add after the `image_processing` gem line in `Gemfile`:

```ruby
gem "streamio-ffmpeg", "~> 3.0"
```

- [ ] **Step 2: Run bundle install**

Run: `cd /Users/edixonhernandez/runmyprocess/brainzlab/vision && bundle install`
Expected: Gem installs successfully, `Gemfile.lock` updated

- [ ] **Step 3: Verify FFmpeg is available**

Run: `ffmpeg -version 2>&1 | head -1`
Expected: Output showing FFmpeg version (e.g., `ffmpeg version 7.x ...`)

If FFmpeg is not installed:
Run: `brew install ffmpeg`

- [ ] **Step 4: Verify whisper.cpp is available or note for later install**

Run: `which whisper-cli 2>/dev/null || which whisper.cpp 2>/dev/null || echo "whisper.cpp not installed"`

If not installed, we'll handle it in Task 3 with a fallback to OpenAI Whisper API via HTTP.

- [ ] **Step 5: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "feat(media): add streamio-ffmpeg gem for video frame extraction"
```

---

## Task 2: Create MediaAnalysis model

**Files:**
- Create: `db/migrate/20260330000001_create_media_analyses.rb`
- Create: `app/models/media_analysis.rb`
- Modify: `app/models/project.rb`
- Create: `spec/factories/media_analyses.rb`

- [ ] **Step 1: Generate migration**

Run: `cd /Users/edixonhernandez/runmyprocess/brainzlab/vision && bin/rails generate migration CreateMediaAnalyses`

Then replace the migration content with:

```ruby
class CreateMediaAnalyses < ActiveRecord::Migration[8.0]
  def change
    create_table :media_analyses, id: :uuid do |t|
      t.references :project, null: false, foreign_key: true, type: :uuid
      t.string :analysis_type, null: false # transcribe, detect_keywords, extract_frames, analyze_video
      t.string :status, null: false, default: "pending" # pending, processing, completed, error
      t.string :source_url, null: false
      t.jsonb :parameters, default: {}
      t.jsonb :result, default: {}
      t.text :error_message
      t.integer :duration_ms
      t.timestamps
    end

    add_index :media_analyses, :status
    add_index :media_analyses, :analysis_type
    add_index :media_analyses, [:project_id, :status]
  end
end
```

- [ ] **Step 2: Create the model**

Create `app/models/media_analysis.rb`:

```ruby
# frozen_string_literal: true

class MediaAnalysis < ApplicationRecord
  belongs_to :project

  TYPES = %w[transcribe detect_keywords extract_frames analyze_video].freeze
  STATUSES = %w[pending processing completed error].freeze

  validates :analysis_type, presence: true, inclusion: { in: TYPES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :source_url, presence: true

  scope :pending, -> { where(status: "pending") }
  scope :processing, -> { where(status: "processing") }
  scope :completed, -> { where(status: "completed") }
  scope :errored, -> { where(status: "error") }

  def start!
    update!(status: "processing")
  end

  def complete!(result_data, duration: nil)
    update!(status: "completed", result: result_data, duration_ms: duration)
  end

  def fail!(message)
    update!(status: "error", error_message: message)
  end

  def finished?
    %w[completed error].include?(status)
  end
end
```

- [ ] **Step 3: Add association to Project**

In `app/models/project.rb`, add after `has_many :credentials, dependent: :destroy`:

```ruby
  has_many :media_analyses, dependent: :destroy
```

- [ ] **Step 4: Run migration**

Run: `cd /Users/edixonhernandez/runmyprocess/brainzlab/vision && bin/rails db:migrate`
Expected: Migration runs successfully

- [ ] **Step 5: Create factory**

Create `spec/factories/media_analyses.rb`:

```ruby
FactoryBot.define do
  factory :media_analysis do
    project
    analysis_type { "transcribe" }
    status { "pending" }
    source_url { "https://s3.example.com/recordings/test-audio.webm" }
    parameters { {} }
    result { {} }

    trait :processing do
      status { "processing" }
    end

    trait :completed do
      status { "completed" }
      duration_ms { 2500 }
    end

    trait :error do
      status { "error" }
      error_message { "Processing failed" }
    end

    trait :transcription do
      analysis_type { "transcribe" }
      parameters { { language: "es" } }
    end

    trait :keyword_detection do
      analysis_type { "detect_keywords" }
      parameters { { keywords: ["plata", "arreglo", "no reportar"] } }
    end

    trait :frame_extraction do
      analysis_type { "extract_frames" }
      parameters { { interval_seconds: 60 } }
    end

    trait :video_analysis do
      analysis_type { "analyze_video" }
      parameters { { prompt: "Count equipment installed" } }
    end
  end
end
```

- [ ] **Step 6: Verify model loads**

Run: `cd /Users/edixonhernandez/runmyprocess/brainzlab/vision && bin/rails runner "puts MediaAnalysis.column_names.inspect"`
Expected: Array of column names including `analysis_type`, `status`, `source_url`, `parameters`, `result`

- [ ] **Step 7: Commit**

```bash
git add db/migrate/ app/models/media_analysis.rb app/models/project.rb spec/factories/media_analyses.rb db/schema.rb
git commit -m "feat(media): add MediaAnalysis model for tracking media processing"
```

---

## Task 3: Implement Media::AudioTranscriber service

**Files:**
- Create: `app/services/media/audio_transcriber.rb`
- Create: `spec/services/media/audio_transcriber_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/services/media/audio_transcriber_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Media::AudioTranscriber do
  let(:audio_url) { "https://s3.example.com/recordings/test.webm" }
  let(:audio_data) { "fake_audio_binary_data" }
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/edixonhernandez/runmyprocess/brainzlab/vision && bundle exec rspec spec/services/media/audio_transcriber_spec.rb`
Expected: FAIL — `uninitialized constant Media::AudioTranscriber`

- [ ] **Step 3: Write the implementation**

Create `app/services/media/audio_transcriber.rb`:

```ruby
# frozen_string_literal: true

module Media
  class AudioTranscriber
    WHISPER_MODEL = ENV.fetch("WHISPER_MODEL", "base")
    WHISPER_BIN = ENV.fetch("WHISPER_BIN", "whisper-cli")

    attr_reader :source_url, :language

    def initialize(source_url, language: "es")
      @source_url = source_url
      @language = language
    end

    def transcribe
      Dir.mktmpdir("vision-audio") do |tmp_dir|
        audio_path = download_file(tmp_dir)
        wav_path = convert_to_wav(audio_path, tmp_dir)

        if whisper_available?
          raw_output = run_whisper(wav_path)
          segments = parse_whisper_output(raw_output)
        else
          Rails.logger.warn "[Media::AudioTranscriber] whisper.cpp not found, falling back to API"
          return transcribe_via_api(wav_path)
        end

        full_text = segments.map { |s| s[:text] }.join(" ")

        {
          segments: segments,
          full_text: full_text,
          language: language,
          engine: "whisper.cpp"
        }
      end
    end

    private

    def download_file(tmp_dir)
      output_path = File.join(tmp_dir, "input#{File.extname(source_url)}")
      uri = URI.parse(source_url)

      Rails.logger.info "[Media::AudioTranscriber] Downloading #{source_url}"

      File.open(output_path, "wb") do |file|
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
          http.request(Net::HTTP::Get.new(uri)) do |response|
            response.read_body { |chunk| file.write(chunk) }
          end
        end
      end

      output_path
    end

    def convert_to_wav(input_path, tmp_dir)
      wav_path = File.join(tmp_dir, "audio.wav")

      system(
        "ffmpeg", "-i", input_path,
        "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le",
        wav_path,
        "-y", "-loglevel", "error",
        exception: true
      )

      wav_path
    end

    def whisper_available?
      system("which", WHISPER_BIN, out: File::NULL, err: File::NULL)
    end

    def run_whisper(wav_path)
      model_path = ENV.fetch("WHISPER_MODEL_PATH", File.expand_path("~/.cache/whisper/ggml-#{WHISPER_MODEL}.bin"))

      cmd = [
        WHISPER_BIN,
        "-m", model_path,
        "-l", language,
        "-f", wav_path,
        "--output-text", "false",
        "--no-timestamps", "false"
      ]

      Rails.logger.info "[Media::AudioTranscriber] Running: #{cmd.join(' ')}"

      output, status = Open3.capture2(*cmd)
      raise "whisper.cpp failed with status #{status.exitstatus}: #{output}" unless status.success?

      output
    end

    def parse_whisper_output(raw_output)
      segments = []

      raw_output.each_line do |line|
        line = line.strip
        next if line.empty?

        if line =~ /\[(\d{2}:\d{2}:\d{2}\.\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}\.\d{3})\]\s*(.*)/
          segments << {
            start: $1,
            end: $2,
            text: $3.strip
          }
        end
      end

      segments
    end

    def transcribe_via_api(wav_path)
      api_key = ENV["OPENAI_API_KEY"]
      raise "Neither whisper.cpp nor OPENAI_API_KEY available for transcription" unless api_key

      uri = URI.parse("https://api.openai.com/v1/audio/transcriptions")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{api_key}"

      form_data = [
        ["file", File.open(wav_path), { filename: "audio.wav", content_type: "audio/wav" }],
        ["model", "whisper-1"],
        ["language", language],
        ["response_format", "verbose_json"],
        ["timestamp_granularities[]", "segment"]
      ]
      request.set_form(form_data, "multipart/form-data")

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      raise "Whisper API failed: #{response.code} #{response.body}" unless response.code == "200"

      data = JSON.parse(response.body)
      segments = (data["segments"] || []).map do |seg|
        {
          start: format_timestamp(seg["start"]),
          end: format_timestamp(seg["end"]),
          text: seg["text"].strip
        }
      end

      {
        segments: segments,
        full_text: data["text"],
        language: language,
        engine: "openai-whisper-api"
      }
    end

    def format_timestamp(seconds)
      hours = (seconds / 3600).to_i
      minutes = ((seconds % 3600) / 60).to_i
      secs = seconds % 60
      format("%02d:%02d:%06.3f", hours, minutes, secs)
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/edixonhernandez/runmyprocess/brainzlab/vision && bundle exec rspec spec/services/media/audio_transcriber_spec.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/media/audio_transcriber.rb spec/services/media/audio_transcriber_spec.rb
git commit -m "feat(media): add AudioTranscriber service with whisper.cpp and API fallback"
```

---

## Task 4: Implement Media::KeywordDetector service

**Files:**
- Create: `app/services/media/keyword_detector.rb`
- Create: `spec/services/media/keyword_detector_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/services/media/keyword_detector_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Media::KeywordDetector do
  let(:segments) do
    [
      { start: "00:00:00.000", end: "00:00:05.000", text: "Buenos dias, vengo a revisar el medidor." },
      { start: "00:00:05.000", end: "00:00:10.000", text: "Ingeniero, no hay forma de arreglar esto sin el reporte?" },
      { start: "00:00:10.000", end: "00:00:15.000", text: "Le puedo dar plata si no reporta nada." },
      { start: "00:00:15.000", end: "00:00:20.000", text: "Dejeme ver que puedo hacer." }
    ]
  end

  let(:keywords) { ["plata", "arreglo", "no reportar", "no reporta", "entre nosotros", "colaboracion"] }

  describe "#detect" do
    it "returns matches with timestamps and context" do
      detector = described_class.new(segments, keywords: keywords)
      result = detector.detect

      expect(result[:matches]).to be_an(Array)
      expect(result[:matches].length).to be >= 3
      expect(result[:matches].map { |m| m[:keyword] }).to include("plata")
      expect(result[:matches].map { |m| m[:keyword] }).to include("arreglar")
    end

    it "calculates a fraud score" do
      detector = described_class.new(segments, keywords: keywords)
      result = detector.detect

      expect(result[:score]).to be_a(Numeric)
      expect(result[:score]).to be > 0
      expect(result[:score]).to be <= 100
    end

    it "includes the timestamp of each match" do
      detector = described_class.new(segments, keywords: keywords)
      result = detector.detect

      plata_match = result[:matches].find { |m| m[:keyword] == "plata" }
      expect(plata_match).not_to be_nil
      expect(plata_match[:timestamp]).to eq("00:00:10.000")
      expect(plata_match[:context]).to include("plata")
    end

    context "when no keywords found" do
      let(:clean_segments) do
        [
          { start: "00:00:00.000", end: "00:00:05.000", text: "Buenos dias, el medidor esta funcionando bien." },
          { start: "00:00:05.000", end: "00:00:10.000", text: "Gracias por su tiempo." }
        ]
      end

      it "returns empty matches and zero score" do
        detector = described_class.new(clean_segments, keywords: keywords)
        result = detector.detect

        expect(result[:matches]).to be_empty
        expect(result[:score]).to eq(0)
      end
    end

    context "with custom weights" do
      it "applies weights to score calculation" do
        weights = { "plata" => 40, "arreglo" => 25, "no reporta" => 35 }
        detector = described_class.new(segments, keywords: keywords, weights: weights)
        result = detector.detect

        expect(result[:score]).to be > 50
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/edixonhernandez/runmyprocess/brainzlab/vision && bundle exec rspec spec/services/media/keyword_detector_spec.rb`
Expected: FAIL — `uninitialized constant Media::KeywordDetector`

- [ ] **Step 3: Write the implementation**

Create `app/services/media/keyword_detector.rb`:

```ruby
# frozen_string_literal: true

module Media
  class KeywordDetector
    DEFAULT_WEIGHT = 15
    MAX_SCORE = 100

    attr_reader :segments, :keywords, :weights

    def initialize(segments, keywords:, weights: {})
      @segments = segments
      @keywords = keywords.map(&:downcase)
      @weights = weights.transform_keys(&:downcase)
    end

    def detect
      matches = find_matches
      score = calculate_score(matches)

      {
        matches: matches,
        score: [score, MAX_SCORE].min,
        keywords_searched: keywords,
        total_segments: segments.length
      }
    end

    private

    def find_matches
      matches = []

      segments.each do |segment|
        text_lower = segment[:text].downcase

        keywords.each do |keyword|
          # Use word-boundary-aware matching for multi-word keywords
          # and substring matching for single words
          pattern = if keyword.include?(" ")
            /#{Regexp.escape(keyword)}/i
          else
            /\b#{Regexp.escape(keyword)}\w*/i
          end

          text_lower.scan(pattern).each do |matched_text|
            matches << {
              keyword: matched_text.strip,
              timestamp: segment[:start],
              segment_end: segment[:end],
              context: segment[:text]
            }
          end
        end
      end

      matches
    end

    def calculate_score(matches)
      return 0 if matches.empty?

      total = matches.sum do |match|
        keyword_base = keywords.find { |k| match[:keyword].downcase.include?(k) } || match[:keyword]
        weights.fetch(keyword_base, DEFAULT_WEIGHT)
      end

      total
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/edixonhernandez/runmyprocess/brainzlab/vision && bundle exec rspec spec/services/media/keyword_detector_spec.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/media/keyword_detector.rb spec/services/media/keyword_detector_spec.rb
git commit -m "feat(media): add KeywordDetector service for fraud keyword scanning"
```

---

## Task 5: Implement Media::VideoFrameExtractor service

**Files:**
- Create: `app/services/media/video_frame_extractor.rb`
- Create: `spec/services/media/video_frame_extractor_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/services/media/video_frame_extractor_spec.rb`:

```ruby
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

        # Simulate frame extraction creating files
        allow(fake_movie).to receive(:screenshot) do |output_path, _opts|
          FileUtils.touch(output_path)
        end
      end

      it "extracts frames at the specified interval" do
        service = described_class.new(video_url, interval_seconds: 60)
        result = service.extract

        expect(result[:frames]).to be_an(Array)
        expect(result[:frames].length).to eq(3) # 180s / 60s = 3 frames
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/edixonhernandez/runmyprocess/brainzlab/vision && bundle exec rspec spec/services/media/video_frame_extractor_spec.rb`
Expected: FAIL — `uninitialized constant Media::VideoFrameExtractor`

- [ ] **Step 3: Write the implementation**

Create `app/services/media/video_frame_extractor.rb`:

```ruby
# frozen_string_literal: true

require "streamio-ffmpeg"

module Media
  class VideoFrameExtractor
    class InvalidVideoError < StandardError; end

    DEFAULT_INTERVAL = 60 # seconds
    FRAME_FORMAT = "jpg"

    attr_reader :source_url, :interval_seconds

    def initialize(source_url, interval_seconds: DEFAULT_INTERVAL)
      @source_url = source_url
      @interval_seconds = interval_seconds
    end

    def extract
      Dir.mktmpdir("vision-video") do |tmp_dir|
        video_path = download_file(tmp_dir)
        movie = FFMPEG::Movie.new(video_path)

        raise InvalidVideoError, "Invalid or corrupt video file" unless movie.valid?

        frames = extract_frames(movie, tmp_dir)

        {
          frames: frames,
          video_duration: movie.duration,
          video_resolution: { width: movie.width, height: movie.height },
          interval_seconds: interval_seconds,
          frame_count: frames.length
        }
      end
    end

    private

    def download_file(tmp_dir)
      ext = File.extname(source_url).presence || ".webm"
      output_path = File.join(tmp_dir, "input#{ext}")
      uri = URI.parse(source_url)

      Rails.logger.info "[Media::VideoFrameExtractor] Downloading #{source_url}"

      File.open(output_path, "wb") do |file|
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
          http.request(Net::HTTP::Get.new(uri)) do |response|
            response.read_body { |chunk| file.write(chunk) }
          end
        end
      end

      output_path
    end

    def extract_frames(movie, tmp_dir)
      frames = []
      timestamp = 0

      while timestamp < movie.duration
        frame_path = File.join(tmp_dir, "frame_#{timestamp.to_i}.#{FRAME_FORMAT}")

        movie.screenshot(frame_path, seek_time: timestamp, resolution: "#{movie.width}x#{movie.height}")

        if File.exist?(frame_path)
          frame_data = File.binread(frame_path)

          frames << {
            timestamp_seconds: timestamp.to_i,
            timestamp_formatted: format_timestamp(timestamp),
            path: frame_path,
            data: Base64.strict_encode64(frame_data),
            size_bytes: frame_data.bytesize
          }
        end

        timestamp += interval_seconds
      end

      Rails.logger.info "[Media::VideoFrameExtractor] Extracted #{frames.length} frames from #{movie.duration}s video"
      frames
    end

    def format_timestamp(seconds)
      hours = (seconds / 3600).to_i
      minutes = ((seconds % 3600) / 60).to_i
      secs = (seconds % 60).to_i
      format("%02d:%02d:%02d", hours, minutes, secs)
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/edixonhernandez/runmyprocess/brainzlab/vision && bundle exec rspec spec/services/media/video_frame_extractor_spec.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/media/video_frame_extractor.rb spec/services/media/video_frame_extractor_spec.rb
git commit -m "feat(media): add VideoFrameExtractor service with FFmpeg"
```

---

## Task 6: Implement Media::VideoAnalyzer service

**Files:**
- Create: `app/services/media/video_analyzer.rb`
- Create: `spec/services/media/video_analyzer_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/services/media/video_analyzer_spec.rb`:

```ruby
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
      allow(fake_llm).to receive(:complete).and_return({
        text: "Summary: 2 meters visible across all frames with serials ABC-123 and DEF-456."
      })

      service = described_class.new(project, video_url, prompt: prompt)
      result = service.analyze

      expect(result[:summary]).to be_a(String)
    end

    it "includes video metadata" do
      service = described_class.new(project, video_url, prompt: prompt)
      result = service.analyze

      expect(result[:video_duration]).to eq(120.0)
      expect(result[:frames_analyzed]).to eq(2)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/edixonhernandez/runmyprocess/brainzlab/vision && bundle exec rspec spec/services/media/video_analyzer_spec.rb`
Expected: FAIL — `uninitialized constant Media::VideoAnalyzer`

- [ ] **Step 3: Write the implementation**

Create `app/services/media/video_analyzer.rb`:

```ruby
# frozen_string_literal: true

module Media
  class VideoAnalyzer
    attr_reader :project, :source_url, :prompt, :interval_seconds, :model

    def initialize(project, source_url, prompt:, interval_seconds: 60, model: nil)
      @project = project
      @source_url = source_url
      @prompt = prompt
      @interval_seconds = interval_seconds
      @model = model || project.settings.dig("ai", "default_model") || "claude-sonnet-4"
    end

    def analyze
      extraction = extract_frames
      frame_analyses = analyze_frames(extraction[:frames])
      summary = generate_summary(frame_analyses)

      {
        frame_analyses: frame_analyses,
        summary: summary,
        video_duration: extraction[:video_duration],
        video_resolution: extraction[:video_resolution],
        frames_analyzed: frame_analyses.length,
        interval_seconds: interval_seconds,
        model: model
      }
    end

    private

    def extract_frames
      extractor = Media::VideoFrameExtractor.new(source_url, interval_seconds: interval_seconds)
      extractor.extract
    end

    def analyze_frames(frames)
      llm = LlmProviders::Factory.for_project(project, model: model)

      frames.map do |frame|
        Rails.logger.info "[Media::VideoAnalyzer] Analyzing frame at #{frame[:timestamp_formatted]}"

        response = llm.analyze_image(
          image_data: frame[:data],
          prompt: prompt,
          format: :base64
        )

        {
          timestamp: frame[:timestamp_formatted],
          timestamp_seconds: frame[:timestamp_seconds],
          analysis: response[:text]
        }
      end
    end

    def generate_summary(frame_analyses)
      return "No frames to analyze" if frame_analyses.empty?

      llm = LlmProviders::Factory.for_project(project, model: model)

      analyses_text = frame_analyses.map do |fa|
        "[#{fa[:timestamp]}] #{fa[:analysis]}"
      end.join("\n\n")

      messages = [
        {
          role: "user",
          content: "Based on the following frame-by-frame analysis of a video, provide a consolidated summary:\n\n" \
                   "Original analysis prompt: #{prompt}\n\n" \
                   "Frame analyses:\n#{analyses_text}\n\n" \
                   "Provide a concise summary of findings across all frames."
        }
      ]

      response = llm.complete(messages: messages)
      response[:text]
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/edixonhernandez/runmyprocess/brainzlab/vision && bundle exec rspec spec/services/media/video_analyzer_spec.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/media/video_analyzer.rb spec/services/media/video_analyzer_spec.rb
git commit -m "feat(media): add VideoAnalyzer service using Claude Vision on extracted frames"
```

---

## Task 7: Implement MediaAnalysisJob

**Files:**
- Create: `app/jobs/media_analysis_job.rb`
- Create: `spec/jobs/media_analysis_job_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/jobs/media_analysis_job_spec.rb`:

```ruby
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/edixonhernandez/runmyprocess/brainzlab/vision && bundle exec rspec spec/jobs/media_analysis_job_spec.rb`
Expected: FAIL — `uninitialized constant MediaAnalysisJob`

- [ ] **Step 3: Write the implementation**

Create `app/jobs/media_analysis_job.rb`:

```ruby
# frozen_string_literal: true

class MediaAnalysisJob < ApplicationJob
  queue_as :media
  retry_on StandardError, wait: :polynomially_longer, attempts: 2
  discard_on ActiveRecord::RecordNotFound

  def perform(media_analysis_id)
    analysis = MediaAnalysis.find(media_analysis_id)
    return if analysis.finished?

    analysis.start!
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    result = case analysis.analysis_type
    when "transcribe"
      run_transcription(analysis)
    when "detect_keywords"
      run_keyword_detection(analysis)
    when "extract_frames"
      run_frame_extraction(analysis)
    when "analyze_video"
      run_video_analysis(analysis)
    else
      raise "Unknown analysis type: #{analysis.analysis_type}"
    end

    duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).to_i
    analysis.complete!(result, duration: duration)

    Rails.logger.info "[MediaAnalysisJob] Completed #{analysis.analysis_type} in #{duration}ms"
  rescue StandardError => e
    analysis&.fail!(e.message) if analysis && !analysis.finished?
    raise
  end

  private

  def run_transcription(analysis)
    language = analysis.parameters["language"] || "es"
    transcriber = Media::AudioTranscriber.new(analysis.source_url, language: language)
    transcriber.transcribe
  end

  def run_keyword_detection(analysis)
    keywords = analysis.parameters["keywords"] || []
    weights = analysis.parameters["weights"] || {}

    # If segments provided directly (from a prior transcription)
    segments = if analysis.parameters["segments"].present?
      analysis.parameters["segments"].map(&:symbolize_keys)
    else
      # Build single segment from raw text
      [{ start: "00:00:00.000", end: "00:00:00.000", text: analysis.parameters["text"] || "" }]
    end

    detector = Media::KeywordDetector.new(segments, keywords: keywords, weights: weights)
    detector.detect
  end

  def run_frame_extraction(analysis)
    interval = analysis.parameters["interval_seconds"] || 60
    extractor = Media::VideoFrameExtractor.new(analysis.source_url, interval_seconds: interval)
    result = extractor.extract
    # Strip binary frame data from stored result to avoid bloating the DB
    result[:frames] = result[:frames].map { |f| f.except(:data, :path) }
    result
  end

  def run_video_analysis(analysis)
    prompt = analysis.parameters["prompt"] || "Describe what you see in this frame."
    interval = analysis.parameters["interval_seconds"] || 60
    model = analysis.parameters["model"]

    analyzer = Media::VideoAnalyzer.new(
      analysis.project,
      analysis.source_url,
      prompt: prompt,
      interval_seconds: interval,
      model: model
    )
    analyzer.analyze
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/edixonhernandez/runmyprocess/brainzlab/vision && bundle exec rspec spec/jobs/media_analysis_job_spec.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/jobs/media_analysis_job.rb spec/jobs/media_analysis_job_spec.rb
git commit -m "feat(media): add MediaAnalysisJob for async media processing"
```

---

## Task 8: Implement MCP tool — vision_transcribe

**Files:**
- Create: `app/services/mcp/tools/vision_transcribe.rb`
- Create: `spec/services/mcp/tools/vision_transcribe_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/services/mcp/tools/vision_transcribe_spec.rb`:

```ruby
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/edixonhernandez/runmyprocess/brainzlab/vision && bundle exec rspec spec/services/mcp/tools/vision_transcribe_spec.rb`
Expected: FAIL — `uninitialized constant Mcp::Tools::VisionTranscribe`

- [ ] **Step 3: Write the implementation**

Create `app/services/mcp/tools/vision_transcribe.rb`:

```ruby
# frozen_string_literal: true

module Mcp
  module Tools
    class VisionTranscribe < Base
      DESCRIPTION = "Transcribe audio to text with timestamps using whisper.cpp (local, free) or OpenAI Whisper API fallback. Returns timestamped segments and full text. Useful for analyzing field recordings, detecting spoken content, and enabling keyword search on audio."

      SCHEMA = {
        type: "object",
        properties: {
          audio_url: {
            type: "string",
            description: "URL of the audio file to transcribe (S3/Spaces URL). Supports WebM, MP3, WAV, OGG."
          },
          language: {
            type: "string",
            default: "es",
            description: "Language code for transcription (e.g., 'es', 'en', 'pt')"
          },
          async: {
            type: "boolean",
            default: false,
            description: "Run asynchronously. Returns analysis_id to poll for results."
          }
        },
        required: %w[audio_url]
      }.freeze

      def call(args)
        audio_url = args[:audio_url]
        return error("audio_url is required") if audio_url.blank?

        language = args[:language] || "es"
        async = args[:async] || false

        if async
          analysis = project.media_analyses.create!(
            analysis_type: "transcribe",
            source_url: audio_url,
            parameters: { language: language }
          )
          MediaAnalysisJob.perform_later(analysis.id)

          success({
            analysis_id: analysis.id,
            status: "pending",
            message: "Transcription queued. Poll /api/v1/media_analyses/#{analysis.id} for results."
          })
        else
          transcriber = Media::AudioTranscriber.new(audio_url, language: language)
          result = transcriber.transcribe

          success({
            segments: result[:segments],
            full_text: result[:full_text],
            language: result[:language],
            engine: result[:engine],
            segment_count: result[:segments].length
          })
        end
      rescue => e
        error("Transcription failed: #{e.message}")
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/edixonhernandez/runmyprocess/brainzlab/vision && bundle exec rspec spec/services/mcp/tools/vision_transcribe_spec.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/mcp/tools/vision_transcribe.rb spec/services/mcp/tools/vision_transcribe_spec.rb
git commit -m "feat(media): add vision_transcribe MCP tool"
```

---

## Task 9: Implement MCP tool — vision_detect_keywords

**Files:**
- Create: `app/services/mcp/tools/vision_detect_keywords.rb`
- Create: `spec/services/mcp/tools/vision_detect_keywords_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/services/mcp/tools/vision_detect_keywords_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Mcp::Tools::VisionDetectKeywords do
  let(:project) { create(:project) }
  let(:tool) { described_class.new(project) }

  let(:segments) do
    [
      { start: "00:00:00.000", end: "00:00:05.000", text: "Le puedo dar plata si no reporta." }
    ]
  end

  let(:keywords) { ["plata", "no reporta", "arreglo"] }

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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/edixonhernandez/runmyprocess/brainzlab/vision && bundle exec rspec spec/services/mcp/tools/vision_detect_keywords_spec.rb`
Expected: FAIL — `uninitialized constant Mcp::Tools::VisionDetectKeywords`

- [ ] **Step 3: Write the implementation**

Create `app/services/mcp/tools/vision_detect_keywords.rb`:

```ruby
# frozen_string_literal: true

module Mcp
  module Tools
    class VisionDetectKeywords < Base
      DESCRIPTION = "Detect suspicious keywords in transcribed text or audio segments. Returns matches with timestamps, context, and a fraud risk score. Designed for analyzing field recordings for bribery, corruption, or equipment theft language."

      SCHEMA = {
        type: "object",
        properties: {
          segments: {
            type: "array",
            description: "Array of transcript segments with {start, end, text} from vision_transcribe output",
            items: {
              type: "object",
              properties: {
                start: { type: "string" },
                end: { type: "string" },
                text: { type: "string" }
              }
            }
          },
          text: {
            type: "string",
            description: "Plain text to scan (alternative to segments). If both provided, segments take precedence."
          },
          keywords: {
            type: "array",
            items: { type: "string" },
            description: "List of keywords/phrases to detect (e.g., ['plata', 'arreglo', 'no reportar'])"
          },
          weights: {
            type: "object",
            description: "Optional keyword weights for score calculation (e.g., {'plata': 30, 'arreglo': 25}). Default weight is 15 per match."
          }
        },
        required: %w[keywords]
      }.freeze

      def call(args)
        keywords = args[:keywords]
        return error("keywords array is required") if keywords.blank?

        segments = if args[:segments].present?
          args[:segments].map { |s| s.transform_keys(&:to_sym) }
        elsif args[:text].present?
          [{ start: "00:00:00.000", end: "00:00:00.000", text: args[:text] }]
        else
          return error("Either segments or text is required")
        end

        weights = (args[:weights] || {}).transform_keys(&:to_s)

        detector = Media::KeywordDetector.new(segments, keywords: keywords, weights: weights)
        result = detector.detect

        success(result)
      rescue => e
        error("Keyword detection failed: #{e.message}")
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/edixonhernandez/runmyprocess/brainzlab/vision && bundle exec rspec spec/services/mcp/tools/vision_detect_keywords_spec.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/mcp/tools/vision_detect_keywords.rb spec/services/mcp/tools/vision_detect_keywords_spec.rb
git commit -m "feat(media): add vision_detect_keywords MCP tool"
```

---

## Task 10: Implement MCP tool — vision_extract_frames

**Files:**
- Create: `app/services/mcp/tools/vision_extract_frames.rb`
- Create: `spec/services/mcp/tools/vision_extract_frames_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/services/mcp/tools/vision_extract_frames_spec.rb`:

```ruby
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/edixonhernandez/runmyprocess/brainzlab/vision && bundle exec rspec spec/services/mcp/tools/vision_extract_frames_spec.rb`
Expected: FAIL — `uninitialized constant Mcp::Tools::VisionExtractFrames`

- [ ] **Step 3: Write the implementation**

Create `app/services/mcp/tools/vision_extract_frames.rb`:

```ruby
# frozen_string_literal: true

module Mcp
  module Tools
    class VisionExtractFrames < Base
      DESCRIPTION = "Extract frames from a video at a specified interval using FFmpeg. Returns frame metadata (timestamps, sizes). Use vision_analyze_video for AI analysis of the frames."

      SCHEMA = {
        type: "object",
        properties: {
          video_url: {
            type: "string",
            description: "URL of the video file (S3/Spaces URL). Supports WebM, MP4."
          },
          interval_seconds: {
            type: "integer",
            default: 60,
            minimum: 1,
            maximum: 600,
            description: "Extract one frame every N seconds (default: 60)"
          },
          async: {
            type: "boolean",
            default: false,
            description: "Run asynchronously. Returns analysis_id to poll for results."
          }
        },
        required: %w[video_url]
      }.freeze

      def call(args)
        video_url = args[:video_url]
        return error("video_url is required") if video_url.blank?

        interval = args[:interval_seconds] || 60
        async = args[:async] || false

        if async
          analysis = project.media_analyses.create!(
            analysis_type: "extract_frames",
            source_url: video_url,
            parameters: { interval_seconds: interval }
          )
          MediaAnalysisJob.perform_later(analysis.id)

          success({
            analysis_id: analysis.id,
            status: "pending",
            message: "Frame extraction queued. Poll /api/v1/media_analyses/#{analysis.id} for results."
          })
        else
          extractor = Media::VideoFrameExtractor.new(video_url, interval_seconds: interval)
          result = extractor.extract

          # Return metadata without binary data
          frames_meta = result[:frames].map { |f| f.except(:data, :path) }

          success({
            frames: frames_meta,
            frame_count: result[:frame_count],
            video_duration: result[:video_duration],
            video_resolution: result[:video_resolution],
            interval_seconds: result[:interval_seconds]
          })
        end
      rescue Media::VideoFrameExtractor::InvalidVideoError => e
        error("Invalid video: #{e.message}")
      rescue => e
        error("Frame extraction failed: #{e.message}")
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/edixonhernandez/runmyprocess/brainzlab/vision && bundle exec rspec spec/services/mcp/tools/vision_extract_frames_spec.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/mcp/tools/vision_extract_frames.rb spec/services/mcp/tools/vision_extract_frames_spec.rb
git commit -m "feat(media): add vision_extract_frames MCP tool"
```

---

## Task 11: Implement MCP tool — vision_analyze_video

**Files:**
- Create: `app/services/mcp/tools/vision_analyze_video.rb`
- Create: `spec/services/mcp/tools/vision_analyze_video_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/services/mcp/tools/vision_analyze_video_spec.rb`:

```ruby
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/edixonhernandez/runmyprocess/brainzlab/vision && bundle exec rspec spec/services/mcp/tools/vision_analyze_video_spec.rb`
Expected: FAIL — `uninitialized constant Mcp::Tools::VisionAnalyzeVideo`

- [ ] **Step 3: Write the implementation**

Create `app/services/mcp/tools/vision_analyze_video.rb`:

```ruby
# frozen_string_literal: true

module Mcp
  module Tools
    class VisionAnalyzeVideo < Base
      DESCRIPTION = "Analyze video content by extracting frames and running AI vision analysis on each. Returns per-frame analysis and a consolidated summary. Use for counting equipment, reading serial numbers, verifying field work, or detecting anomalies in recorded inspections."

      SCHEMA = {
        type: "object",
        properties: {
          video_url: {
            type: "string",
            description: "URL of the video file (S3/Spaces URL). Supports WebM, MP4."
          },
          prompt: {
            type: "string",
            description: "Analysis prompt for each frame (e.g., 'How many meters installed? Read serial numbers.')"
          },
          interval_seconds: {
            type: "integer",
            default: 60,
            minimum: 1,
            maximum: 600,
            description: "Analyze one frame every N seconds (default: 60)"
          },
          model: {
            type: "string",
            enum: %w[claude-sonnet-4 claude-opus-4 gpt-4o gemini-2.5-flash],
            description: "LLM model for vision analysis (default: project setting or claude-sonnet-4)"
          },
          async: {
            type: "boolean",
            default: false,
            description: "Run asynchronously. Returns analysis_id to poll for results."
          }
        },
        required: %w[video_url prompt]
      }.freeze

      def call(args)
        video_url = args[:video_url]
        prompt = args[:prompt]
        return error("video_url is required") if video_url.blank?
        return error("prompt is required") if prompt.blank?

        interval = args[:interval_seconds] || 60
        model = args[:model]
        async = args[:async] || false

        if async
          analysis = project.media_analyses.create!(
            analysis_type: "analyze_video",
            source_url: video_url,
            parameters: { prompt: prompt, interval_seconds: interval, model: model }.compact
          )
          MediaAnalysisJob.perform_later(analysis.id)

          success({
            analysis_id: analysis.id,
            status: "pending",
            message: "Video analysis queued. Poll /api/v1/media_analyses/#{analysis.id} for results."
          })
        else
          analyzer = Media::VideoAnalyzer.new(
            project, video_url,
            prompt: prompt,
            interval_seconds: interval,
            model: model
          )
          result = analyzer.analyze

          success(result)
        end
      rescue Media::VideoFrameExtractor::InvalidVideoError => e
        error("Invalid video: #{e.message}")
      rescue => e
        error("Video analysis failed: #{e.message}")
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/edixonhernandez/runmyprocess/brainzlab/vision && bundle exec rspec spec/services/mcp/tools/vision_analyze_video_spec.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/mcp/tools/vision_analyze_video.rb spec/services/mcp/tools/vision_analyze_video_spec.rb
git commit -m "feat(media): add vision_analyze_video MCP tool"
```

---

## Task 12: Register tools in MCP Server

**Files:**
- Modify: `app/services/mcp/server.rb`

- [ ] **Step 1: Add tool registrations to server.rb**

In `app/services/mcp/server.rb`, add after the `"vision_credential"` entry in the TOOLS hash:

```ruby
      # Media analysis tools
      "vision_transcribe" => Tools::VisionTranscribe,
      "vision_detect_keywords" => Tools::VisionDetectKeywords,
      "vision_extract_frames" => Tools::VisionExtractFrames,
      "vision_analyze_video" => Tools::VisionAnalyzeVideo
```

- [ ] **Step 2: Verify tools are registered**

Run: `cd /Users/edixonhernandez/runmyprocess/brainzlab/vision && bin/rails runner "puts Mcp::Server.new(Project.new).list_tools.map { |t| t[:name] }.sort"`
Expected: Output includes `vision_analyze_video`, `vision_detect_keywords`, `vision_extract_frames`, `vision_transcribe` among the existing tools

- [ ] **Step 3: Commit**

```bash
git add app/services/mcp/server.rb
git commit -m "feat(media): register 4 new media analysis MCP tools in server"
```

---

## Task 13: Run full test suite

- [ ] **Step 1: Run all new media tests**

Run: `cd /Users/edixonhernandez/runmyprocess/brainzlab/vision && bundle exec rspec spec/services/media/ spec/jobs/media_analysis_job_spec.rb spec/services/mcp/tools/vision_transcribe_spec.rb spec/services/mcp/tools/vision_detect_keywords_spec.rb spec/services/mcp/tools/vision_extract_frames_spec.rb spec/services/mcp/tools/vision_analyze_video_spec.rb`
Expected: All tests PASS

- [ ] **Step 2: Run the full existing test suite to check for regressions**

Run: `cd /Users/edixonhernandez/runmyprocess/brainzlab/vision && bundle exec rspec`
Expected: All existing tests still PASS, no regressions

- [ ] **Step 3: Final commit if any fixes were needed**

Only if tests required fixes:
```bash
git add -A
git commit -m "fix(media): test suite fixes for media analysis integration"
```
