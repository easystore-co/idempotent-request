module IdempotentRequest
  class Policy
    attr_reader :request, :config

    def initialize(request, config)
      @request = request
      @config = config
    end

    def should?
      !matching_route.nil?
    end

    def expire_time_for_request
      matching_route&.dig(:expire_time) || config[:expire_time] || 3600
    end

    private

    def matching_route
      return if config[:routes].nil? || config[:routes].empty?

      @matching_route ||= config[:routes].find do |idempotent_route|
        path_matches?(idempotent_route[:path], request.path) &&
          idempotent_route[:http_method] == request.request_method
      end
    end
    
    # Checks if a request path matches a configured path pattern with wildcard support
    def path_matches?(pattern, path)
      # Normalize paths by removing trailing slashes
      normalized_pattern = pattern.chomp('/')
      normalized_path = path.chomp('/')
      
      return normalized_pattern == normalized_path unless normalized_pattern.include?('*')

      # Convert wildcard pattern to regex
      regex_pattern = Regexp.new("^#{Regexp.escape(normalized_pattern).gsub('\*', '([^/]*)')}$")
      regex_pattern.match?(normalized_path)
    end
  end
end
