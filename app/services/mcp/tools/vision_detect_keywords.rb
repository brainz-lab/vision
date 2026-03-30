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
