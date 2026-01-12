# PlatformClient handles communication with the Brainz Lab Platform service
# for API key validation and usage tracking.

class PlatformClient
  # Cache durations
  VALID_KEY_CACHE_TTL = 5.minutes
  INVALID_KEY_CACHE_TTL = 30.seconds  # Short TTL for invalid keys to allow quick retry after fix

  class << self
    def validate_key(raw_key)
      return invalid_response unless raw_key.present?

      # Check cache first
      cache_key = "platform_key_validation:#{Digest::SHA256.hexdigest(raw_key)}"
      cached = Rails.cache.read(cache_key)
      return cached if cached.present?

      result = validate_key_uncached(raw_key)

      # Cache the result (shorter TTL for invalid keys)
      ttl = result[:valid] ? VALID_KEY_CACHE_TTL : INVALID_KEY_CACHE_TTL
      Rails.cache.write(cache_key, result, expires_in: ttl)

      result
    end

    def validate_key_uncached(raw_key)
      response = make_request("/api/v1/keys/validate", { key: raw_key })

      if response[:valid]
        {
          valid: true,
          project_id: response[:project_id],
          project_name: response[:project_name],
          environment: response[:environment] || "production",
          features: response[:features] || { vision: true },
          limits: response[:limits] || {}
        }
      else
        invalid_response
      end
    rescue => e
      Rails.logger.error "Platform validation failed: #{e.message}"
      # In development, allow bypass
      if Rails.env.development?
        {
          valid: true,
          project_id: "dev_#{raw_key.first(8)}",
          project_name: "Development Project",
          environment: "development",
          features: { vision: true },
          limits: {}
        }
      else
        invalid_response
      end
    end

    def track_usage(project_id:, product:, metric:, count:)
      Thread.new do
        make_request("/api/v1/usage/track", {
          project_id: project_id,
          product: product,
          metric: metric,
          count: count
        })
      rescue => e
        Rails.logger.error "Usage tracking failed: #{e.message}"
      end
    end

    private

    def invalid_response
      { valid: false }
    end

    def make_request(path, body)
      uri = URI.parse("#{platform_url}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 10

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request["X-Service-Key"] = service_key if service_key.present?
      request.body = body.to_json

      response = http.request(request)

      if response.code.to_i == 200
        JSON.parse(response.body, symbolize_names: true)
      else
        Rails.logger.warn "Platform returned #{response.code}: #{response.body}"
        { valid: false }
      end
    end

    def platform_url
      ENV.fetch("BRAINZLAB_PLATFORM_URL", "http://platform:3000")
    end

    def service_key
      ENV["SERVICE_KEY"]
    end
  end
end
