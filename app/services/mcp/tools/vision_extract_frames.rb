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
