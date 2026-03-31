# frozen_string_literal: true

require "streamio-ffmpeg"

module Media
  class VideoFrameExtractor
    class InvalidVideoError < StandardError; end

    DEFAULT_INTERVAL = 60
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
