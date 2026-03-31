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
