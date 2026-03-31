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
