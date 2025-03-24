module IdempotentRequest
  class Middleware
    def initialize(app, config = {})
      @app = app
      @config = config.merge(load_config())
      @policy = @config.fetch(:policy)
      @notifier = ActiveSupport::Notifications if defined?(ActiveSupport::Notifications)
      @concurrent_response_status = @config.fetch(:concurrent_response_status, 429)
      @replayed_response_header = @config.fetch(:replayed_response_header, 'Idempotency-Replayed')
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

    def storage
      @storage ||= RequestManager.new(request, config.merge(expire_time: expire_time_for_route))
    end

    def expire_time_for_route
      policy_instance = policy.new(request, config)
      policy_instance.respond_to?(:expire_time_for_route) ? policy_instance.expire_time_for_route : nil
    end

    def read_idempotent_request
      result = storage.read rescue nil
      return if result.blank?

      status, headers, response = result
      headers.merge!(@replayed_response_header => true)
      request.env['idempotent.request']['read'] = [status, headers, response]
    end

    def write_idempotent_request
      begin
        return unless storage.lock
      rescue
        request.env['idempotent.request']['error'] = 'Failed to lock the key'
      end

      result = app.call(request.env)

      begin
        storage.write(*result)
        request.env['idempotent.request']['write'] = result
      rescue
      end

      request.env['idempotent.request']['unlocked'] = storage.unlock rescue nil

      result
    end

    def concurrent_request_response
      status = @concurrent_response_status
      headers = { 'Content-Type' => 'application/json' }
      body = [
        {
          error: {
            type: "TooManyRequests",
            message: "Concurrent requests detected",
            code: "too_many_requests"
          }
        }.to_json
      ]
      request.env['idempotent.request']['concurrent_request_response'] = true
      Rack::Response.new(body, status, headers).finish
    end

    attr_reader :app, :env, :config, :request, :policy, :notifier

    def process?
      !request.key.to_s.empty? && should_be_idempotent?
    end

    def should_be_idempotent?
      return false unless policy
      policy.new(request, config).should?
    end

    def instrument(request)
      notifier.instrument('idempotent.request', request: request) if notifier
    end

    def set_request(env)
      @env = env
      @request ||= Request.new(env, config)
    end

    def load_config(config_file = Rails.root.join('config', 'idempotent.yml'))
      return {} unless File.exist?(config_file)

      config = YAML.load_file(config_file).deep_symbolize_keys
      env = Rails.env.to_s.to_sym

      # Use environment specific settings if available, otherwise use default
      config[env] || config[:default] || {}
    end
  end
end
