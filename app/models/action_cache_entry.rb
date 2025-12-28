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

    # Batch store multiple cache entries using upsert_all to avoid N+1
    # @param project [Project] The project to store entries for
    # @param entries [Array<Hash>] Array of { url:, action:, action_data: }
    # @param instruction [String, nil] Optional instruction to hash for matching
    def batch_store(project:, entries:, instruction: nil)
      return if entries.empty?

      instruction_hash = instruction ? Digest::SHA256.hexdigest(instruction)[0..15] : nil
      now = Time.current
      expires = 24.hours.from_now

      # Group entries by unique key to handle duplicates within the same batch
      grouped = entries.group_by do |entry|
        [url_to_pattern(entry[:url]), entry[:action].to_s]
      end

      # Build records for upsert, merging duplicates
      records = grouped.map do |(url_pattern, action_type), group_entries|
        # Use the last action_data in case of duplicates
        {
          id: SecureRandom.uuid,
          project_id: project.id,
          url_pattern: url_pattern,
          action_type: action_type,
          action_data: group_entries.last[:action_data],
          instruction_hash: instruction_hash,
          success_count: group_entries.size,
          failure_count: 0,
          last_used_at: now,
          expires_at: expires,
          created_at: now,
          updated_at: now
        }
      end

      # Use a single transaction with batch upsert logic
      # We use find_or_create pattern with update to handle the increment
      ActiveRecord::Base.transaction do
        # First, find all existing entries in a single query
        existing_keys = records.map { |r| [r[:project_id], r[:url_pattern], r[:action_type], r[:instruction_hash]] }

        existing_entries = where(project_id: project.id)
          .where(url_pattern: records.map { |r| r[:url_pattern] })
          .where(action_type: records.map { |r| r[:action_type] })
          .where(instruction_hash: instruction_hash)
          .index_by { |e| [e.project_id, e.url_pattern, e.action_type, e.instruction_hash] }

        updates = []
        inserts = []

        records.each do |record|
          key = [record[:project_id], record[:url_pattern], record[:action_type], record[:instruction_hash]]
          if (existing = existing_entries[key])
            updates << {
              id: existing.id,
              success_count: existing.success_count + record[:success_count],
              last_used_at: now,
              expires_at: expires,
              action_data: record[:action_data],
              updated_at: now
            }
          else
            inserts << record
          end
        end

        # Batch insert new records
        if inserts.any?
          insert_all(inserts)
        end

        # Batch update existing records using a single UPDATE with CASE
        if updates.any?
          ids = updates.map { |u| u[:id] }
          success_counts = updates.map { |u| [u[:id], u[:success_count]] }.to_h
          action_data_map = updates.map { |u| [u[:id], u[:action_data]] }.to_h

          # Build CASE statement for success_count
          success_case = "CASE id " + updates.map { |u|
            "WHEN '#{u[:id]}' THEN #{u[:success_count]}"
          }.join(" ") + " END"

          # Build CASE statement for action_data
          action_data_case = "CASE id " + updates.map { |u|
            sanitized_json = connection.quote(u[:action_data].to_json)
            "WHEN '#{u[:id]}' THEN #{sanitized_json}::jsonb"
          }.join(" ") + " END"

          where(id: ids).update_all(
            [
              "success_count = #{success_case}, " \
              "action_data = #{action_data_case}, " \
              "last_used_at = ?, expires_at = ?, updated_at = ?",
              now, expires, now
            ]
          )
        end
      end
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

  # Class method to batch record successes
  def self.batch_record_successes(entry_ids)
    return if entry_ids.empty?

    now = Time.current
    where(id: entry_ids).update_all(
      ["success_count = success_count + 1, last_used_at = ?, updated_at = ?", now, now]
    )
  end

  # Class method to batch record failures
  def self.batch_record_failures(entry_ids)
    return if entry_ids.empty?

    now = Time.current
    where(id: entry_ids).update_all(
      ["failure_count = failure_count + 1, updated_at = ?", now]
    )

    # Check for entries that need invalidation
    invalidate_unreliable(entry_ids)
  end

  # Invalidate entries that have too many failures
  def self.invalidate_unreliable(entry_ids)
    where(id: entry_ids)
      .where("failure_count > 3 AND failure_count > success_count / 2")
      .delete_all
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
