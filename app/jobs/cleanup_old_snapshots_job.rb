class CleanupOldSnapshotsJob < ApplicationJob
  queue_as :low

  # Default retention period (30 days)
  RETENTION_DAYS = ENV.fetch("SNAPSHOT_RETENTION_DAYS", 30).to_i

  def perform
    cutoff_date = RETENTION_DAYS.days.ago

    # Find old snapshots that are not baselines
    old_snapshots = Snapshot.where("created_at < ?", cutoff_date)
                            .where.not(id: Baseline.select(:id))

    count = old_snapshots.count
    Rails.logger.info "Cleaning up #{count} old snapshots older than #{cutoff_date}"

    old_snapshots.find_each do |snapshot|
      # Delete associated files
      snapshot.screenshot.purge if snapshot.screenshot.attached?
      snapshot.thumbnail.purge if snapshot.thumbnail.attached?

      # Delete comparison files
      if snapshot.comparison&.diff_image&.attached?
        snapshot.comparison.diff_image.purge
      end

      snapshot.destroy
    end

    Rails.logger.info "Cleaned up #{count} old snapshots"
  end
end
