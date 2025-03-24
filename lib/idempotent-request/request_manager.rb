module IdempotentRequest
  class RequestManager
    attr_reader :request, :storage, :expire_time

    def initialize(request, config)
      @request = request
      @storage = config.fetch(:storage)
      @expire_time = config[:expire_time]
      @callback = config[:callback]
    end

    def lock
      storage.lock(key, expire_time)
    end

    def unlock
      storage.unlock(key)
    end

    def read
      status, headers, response = parse_data(storage.read(key)).values

      return unless status
      run_callback(:detected, key: key)
      [status, headers, response]
    end

    def write(*data)
      status, headers, response = data
      response = response.body if response.respond_to?(:body)

      if (200..226).cover?(status)
        storage.write(key, payload(status, headers, response), expire_time)
      end

      data
    end

    private

    def parse_data(data)
      return {} if data.to_s.empty?

      Oj.load(data)
    end

    def payload(status, headers, response)
      Oj.dump(status: status,
              headers: headers.to_h,
              response: Array(response))
    end

    def run_callback(action, **args)
      return unless @callback

      @callback.new(request).send(action, **args)
    end

    def key
      request.key
    end
  end
end
