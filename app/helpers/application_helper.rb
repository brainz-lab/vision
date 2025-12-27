# frozen_string_literal: true

module ApplicationHelper
  # Returns a Rails-proxied URL for ActiveStorage attachments
  #
  # Uses proxy mode so Rails streams the file directly to the browser,
  # avoiding hostname issues with S3/MinIO URLs.
  #
  # Accepts either:
  # - ActiveStorage::Attached::One (e.g., @baseline.screenshot)
  # - ActiveStorage::Attachment (when iterating over has_many_attached)
  def public_storage_url(attachment)
    return nil if attachment.nil?

    # For Attached::One/Many proxies, check if attached
    if attachment.respond_to?(:attached?)
      return nil unless attachment.attached?
    end

    # Use Rails storage proxy which streams through Rails (no redirect to S3)
    blob = attachment.respond_to?(:blob) ? attachment.blob : attachment
    rails_storage_proxy_path(blob, disposition: :inline)
  end
end
