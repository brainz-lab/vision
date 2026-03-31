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
