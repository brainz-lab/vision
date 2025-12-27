# frozen_string_literal: true

# Caches successful browser actions for replay without LLM
# Enables faster execution of repeated tasks
class ActionCacheEntry < ApplicationRecord
  belongs_to :project

  # Action types that can be cached
  CACHEABLE_ACTIONS = %w[click type fill select scroll navigate].freeze

  # Validations
  validates :url_pattern, presence: true
  validates :action_type, presence: true, inclusion: { in: CACHEABLE_ACTIONS }
  validates :action_data, presence: true

  # Scopes
  scope :active, -> { where("expires_at > ? OR expires_at IS NULL", Time.current) }
  scope :expired, -> { where("expires_at <= ?", Time.current) }
  scope :by_url, ->(url) { where("? LIKE url_pattern OR url_pattern = ?", url, url_to_pattern(url)) }
  scope :by_action, ->(action) { where(action_type: action) }
  scope :reliable, -> { where("success_count > failure_count * 2") }
  scope :most_used, -> { order(success_count: :desc) }
  scope :recently_used, -> { order(last_used_at: :desc) }

  # Class methods
  class << self
    # Store a successful action in the cache
    def store(project:, url:, action:, action_data:, instruction: nil)
      pattern = url_to_pattern(url)
      instruction_hash = instruction ? Digest::SHA256.hexdigest(instruction)[0..15] : nil

      entry = find_or_initialize_by(
        project: project,
        url_pattern: pattern,
        action_type: action,
        instruction_hash: instruction_hash
      )

      entry.action_data = action_data
      entry.success_count = (entry.success_count || 0) + 1
      entry.last_used_at = Time.current
      entry.expires_at = 24.hours.from_now
      entry.save!

      entry
    end

    # Find cached actions for a URL and action type
    def lookup(project:, url:, action_type: nil, instruction: nil)
      scope = active.where(project: project).by_url(url)
      scope = scope.by_action(action_type) if action_type
      scope = scope.where(instruction_hash: Digest::SHA256.hexdigest(instruction)[0..15]) if instruction
      scope.reliable.most_used.first
    end

    # Find a sequence of cached actions for a URL
    def find_sequence(project:, url:, limit: 10)
      active
        .where(project: project)
        .by_url(url)
        .reliable
        .order(created_at: :asc)
        .limit(limit)
    end

    # Clean up expired entries
    def cleanup_expired!
      expired.delete_all
    end

    # Convert URL to a pattern for matching
    def url_to_pattern(url)
      return url if url.include?("%")

      uri = URI.parse(url)
      # Keep host and path, remove query params for pattern matching
      "#{uri.host}#{uri.path}"
    rescue URI::InvalidURIError
      url
    end
  end

  # Instance methods

  # Record a successful use of this cached action
  def record_success!(duration_ms: nil)
    self.success_count += 1
    self.last_used_at = Time.current

    if duration_ms
      self.avg_duration_ms = if avg_duration_ms.nil?
        duration_ms
      else
        ((avg_duration_ms * (success_count - 1)) + duration_ms) / success_count
      end
    end

    save!
  end

  # Record a failed use of this cached action
  def record_failure!
    self.failure_count += 1
    save!

    # Invalidate if too many failures
    invalidate! if should_invalidate?
  end

  # Check if this cache entry should be invalidated
  def should_invalidate?
    failure_count > 3 && failure_count > success_count / 2
  end

  # Invalidate this cache entry
  def invalidate!
    destroy
  end

  # Check if this entry is reliable
  def reliable?
    success_count > failure_count * 2
  end

  # Check if this entry is expired
  def expired?
    expires_at.present? && expires_at < Time.current
  end

  # Success rate as percentage
  def success_rate
    total = success_count + failure_count
    return 100.0 if total.zero?

    (success_count.to_f / total * 100).round(1)
  end

  def detail
    {
      id: id,
      url_pattern: url_pattern,
      action_type: action_type,
      action_data: action_data,
      success_count: success_count,
      failure_count: failure_count,
      success_rate: success_rate,
      avg_duration_ms: avg_duration_ms&.round,
      last_used_at: last_used_at,
      expires_at: expires_at
    }
  end
end
