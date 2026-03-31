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
