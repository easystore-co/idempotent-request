module IdempotentRequest
  class RedisStorage
    attr_reader :redis, :namespace

    def initialize(redis, namespace: 'idempotency_keys')
      @redis = redis
      @namespace = namespace
    end

    def lock(key, expire_time = nil)
      options = {nx: true}
      if expire_time && expire_time.to_i > 0
        options[:ex] = expire_time.to_i
      end
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
      if expire_time && expire_time.to_i > 0
        options[:ex] = expire_time.to_i
      end
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
