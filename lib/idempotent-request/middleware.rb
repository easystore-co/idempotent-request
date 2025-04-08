module IdempotentRequest
  class Middleware
    def initialize(app, config = {})
      @app = app
      @config = config.merge(load_config(config.fetch(:config_file, 'config/idempotency.yml')))
      @concurrent_response_status = @config.fetch(:concurrent_response_status, 429)
      @replayed_response_header = @config.fetch(:replayed_response_header, 'Idempotency-Replayed')
      @notifier = ActiveSupport::Notifications if defined?(ActiveSupport::Notifications)
    end

    def call(env)
      # dup the middleware to be thread-safe
      dup.process(env)
    end

    def process(env)
      set_request(env)
      return app.call(request.env) unless process?
      request.env['idempotent.request'] = { key: request.key }
      response = read_idempotent_request || write_idempotent_request || concurrent_request_response
      instrument(request)
      response
    end

    private

    def policy
      @policy ||= config.fetch(:policy, IdempotentRequest::Policy).new(request, config)
    end

    def storage
      @storage ||= RequestManager.new(request, config.merge(expire_time: expire_time_for_request))
    end

    def expire_time_for_request
      policy.respond_to?(:expire_time_for_request) ? policy.expire_time_for_request : config[:expire_time]
    end

    def read_idempotent_request
      result = storage.read
      return unless result

      status, headers, response = result
      headers.merge!(@replayed_response_header => true)
      request.env['idempotent.request']['read'] = [status, headers, response]
    end

    def write_idempotent_request
      # Only consider 'false' lock result as key existed, and treat as concurrent request
      # Consider 'true', nil, or other values as key not existed, and continue as normal request
      return if storage.lock == false

      begin
        result = app.call(request.env)
        storage.write(*result)
        request.env['idempotent.request']['write'] = result
      ensure
        request.env['idempotent.request']['unlocked'] = storage.unlock
      end

      result
    end

    def concurrent_request_response
      status = @concurrent_response_status
      headers = { 'Content-Type' => 'application/json' }
      body = [
        Oj.dump("error" => {
          "type" => "TooManyRequests",
          "message" => "Concurrent requests detected",
          "code" => "too_many_requests"
        })
      ]
      request.env['idempotent.request']['concurrent_request_response'] = true
      Rack::Response.new(body, status, headers).finish
    end

    attr_reader :app, :env, :config, :request, :notifier

    def process?
      !request.key.to_s.empty? && policy.should?
    end

    def instrument(request)
      notifier.instrument('idempotent.request', request: request) if notifier
    end

    def set_request(env)
      @env = env
      @request ||= Request.new(env, config)
    end

    def load_config(config_file)
      return {} unless File.exist?(config_file)
      
      config = YAML.load_file(config_file) || {}

      if config.respond_to? :deep_symbolize_keys!
        config.deep_symbolize_keys!
      else
        symbolize_keys_deep!(config)
      end

      environment = ENV["APP_ENV"] || ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "default"
      config[environment.to_sym] || {}
    end
    
    def symbolize_keys_deep!(hash)
      hash.keys.each do |k|
        symkey = k.respond_to?(:to_sym) ? k.to_sym : k
        hash[symkey] = hash.delete k
        symbolize_keys_deep! hash[symkey] if hash[symkey].is_a? Hash
      end
    end
  end
end
