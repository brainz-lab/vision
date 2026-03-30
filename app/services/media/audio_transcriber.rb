# frozen_string_literal: true

require "open3"
require "net/http"

module Media
  class AudioTranscriber
    WHISPER_MODEL = ENV.fetch("WHISPER_MODEL", "base")
    WHISPER_BIN = ENV.fetch("WHISPER_BIN", "whisper-cli")

    WhisperNotAvailableError = Class.new(StandardError)

    attr_reader :source_url, :language

    def initialize(source_url, language: "es")
      @source_url = source_url
      @language = language
    end

    def transcribe
      Dir.mktmpdir("vision-audio") do |tmp_dir|
        audio_path = download_file(tmp_dir)
        wav_path = convert_to_wav(audio_path, tmp_dir)

        begin
          raw_output = run_whisper(wav_path)
          segments = parse_whisper_output(raw_output)

          full_text = segments.map { |s| s[:text] }.join(" ")

          {
            segments: segments,
            full_text: full_text,
            language: language,
            engine: "whisper.cpp"
          }
        rescue WhisperNotAvailableError
          Rails.logger.warn "[Media::AudioTranscriber] whisper.cpp not found, falling back to API"
          transcribe_via_api(wav_path)
        end
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
      raise WhisperNotAvailableError, "whisper.cpp binary '#{WHISPER_BIN}' not found in PATH" unless whisper_available?

      model_path = ENV.fetch("WHISPER_MODEL_PATH", File.expand_path("~/.cache/whisper/ggml-#{WHISPER_MODEL}.bin"))

      cmd = [
        WHISPER_BIN,
        "-m", model_path,
        "-l", language,
        "-f", wav_path,
        "--no-prints"
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
