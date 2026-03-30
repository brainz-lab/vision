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

    segments = if analysis.parameters["segments"].present?
      analysis.parameters["segments"].map(&:symbolize_keys)
    else
      [{ start: "00:00:00.000", end: "00:00:00.000", text: analysis.parameters["text"] || "" }]
    end

    detector = Media::KeywordDetector.new(segments, keywords: keywords, weights: weights)
    detector.detect
  end

  def run_frame_extraction(analysis)
    interval = analysis.parameters["interval_seconds"] || 60
    extractor = Media::VideoFrameExtractor.new(analysis.source_url, interval_seconds: interval)
    result = extractor.extract
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
