module IdempotentRequest
  class RedisStorage
    attr_reader :redis, :namespace, :default_expire_time

    def initialize(redis, config = {})
      @redis = redis
      @namespace = config.fetch(:namespace, 'idempotency_keys')
      @default_expire_time = config[:expire_time]
    end

    def lock(key, expire_time = nil)
      options = {nx: true}
      options[:ex] = expire_time && expire_time.to_i > 0 ?
        expire_time.to_i :
        default_expire_time

      redis.set(lock_key(key), Time.now.to_f, **options)
    end

    def unlock(key)
      redis.del(lock_key(key))
    end

    def read(key)
      redis.get(namespaced_key(key))
    end

    def write(key, payload, expire_time = nil)
      options = {}
      options[:ex] = expire_time && expire_time.to_i > 0 ?
        expire_time.to_i :
        default_expire_time

      redis.set(namespaced_key(key), payload, **options)
    end

    private
    
    def lock_key(key)
      namespaced_key("lock:#{key}")
    end

    def namespaced_key(key)
      [namespace, key.strip]
        .compact
        .join(':')
        .downcase
    end
  end
end
