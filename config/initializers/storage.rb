# Storage configuration for Vision
# Configures S3/MinIO for screenshot storage

Rails.application.config.to_prepare do
  # Ensure the screenshots bucket exists in MinIO (development)
  if Rails.env.development? && ENV['AWS_ENDPOINT'].present?
    require 'aws-sdk-s3'

    begin
      s3 = Aws::S3::Client.new(
        access_key_id: ENV.fetch('AWS_ACCESS_KEY_ID', 'minioadmin'),
        secret_access_key: ENV.fetch('AWS_SECRET_ACCESS_KEY', 'minioadmin'),
        region: ENV.fetch('AWS_REGION', 'us-east-1'),
        endpoint: ENV.fetch('AWS_ENDPOINT', 'http://minio:9000'),
        force_path_style: true
      )

      bucket_name = ENV.fetch('AWS_BUCKET', 'vision-screenshots')

      begin
        s3.head_bucket(bucket: bucket_name)
      rescue Aws::S3::Errors::NotFound
        s3.create_bucket(bucket: bucket_name)
        Rails.logger.info "Created S3 bucket: #{bucket_name}"
      end
    rescue => e
      Rails.logger.warn "Could not initialize S3 storage: #{e.message}"
    end
  end
end
