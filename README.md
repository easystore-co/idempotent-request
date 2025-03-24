# Idempotent Request for Ruby on Rails

Rack middleware ensuring at most once requests for mutating endpoints.

## How does idempotency mechanism works?

1.  Front-end generates a unique `key` then a user goes to a specific route (for example, transfer page).
2.  When user clicks "Submit" button, the `key` is sent in the header `idempotency-key` and back-end stores server response into redis.
3.  All the consecutive requests with the `key` won't be executer by the server and the result of previous response (2) will be fetched from redis.
4.  Once the user leaves or refreshes the page, front-end should re-generate the key.


## Installation

Add this line to your application's Gemfile:

```ruby
gem 'idempotent-request', git: "https://github.com/easystore-co/idempotent-request.git"
```

And then execute:

    $ bundle install

## API
| Parameter | Description | Required/Optional |
| --------- | ----------- | ----------------- |
| storage | The storage instance that use to store the lock and cached response of idempotent requests | Required |
| policy | The class that control this request should execute idempotency mechanism or not. Default will be referring to the config file (`config/idempotent.yml`) | Optional |
| callback | The callback handler | Optional |
| config_file | Customise the configuration file path. Default: `config/idempotent.yml` | Optional |


### Example of Usage
```ruby
# application.rb
config.middleware.use IdempotentRequest::Middleware,
  storage: IdempotentRequest::RedisStorage.new(::Redis.current),
  policy: IdempotentRequest::Policy,
  callback: IdempotentRequest::RailsCallback,
  config_file: 'custom/idempotent/settings.yml'
```

### Configuration File

The configuration YAML file defines how the idempotency mechanism behaves. Default reading `config/idempotent.yml`

#### Configuration Options

| Option | Description | Default |
| ------ | ----------- | ------- |
| `expire_time` | Time in seconds for how long the idempotency keys remain valid | 3600 (1 hour) |
| `concurrent_response_status` | HTTP status code returned when a concurrent request with the same key is detected | 429 |
| `replayed_response_header` | HTTP header name that will be added to responses that are served from cache | Idempotency-Replayed |
| `header_key` | The HTTP header key that contains the idempotency key | Idempotency-Key |
| `routes` | Array of route configurations to specify which endpoints should be idempotent | [] |

#### Route Configuration

Each route entry can have the following options:

| Option | Description | Required |
| ------ | ----------- | -------- |
| `path` | URL path pattern (supports wildcards) | Yes |
| `http_method` | HTTP method (GET, POST, PUT, PATCH, DELETE) | Yes |
| `expire_time` | Override default expiration time for this route | No |


#### Example
```yaml
default: &default
  # How long idempotency keys are valid (in seconds)
  expire_time: 3600
  
  # HTTP status code returned for concurrent requests
  concurrent_response_status: 429
  
  # HTTP header name for indicating replayed responses
  replayed_response_header: Idempotency-Replayed
  
  # The HTTP header key that contains the idempotency key
  header_key: Idempotency-Key
  
  # Route-specific configurations
  routes:
    - path: /api/v1/test/*     # Path pattern (supports wildcards)
      http_method: POST        # HTTP method to make idempotent
      expire_time: 180         # Override default expire time for this route
```


### Custom Options

### Policy
Custom class to decide whether the request should be idempotent.

```ruby
# lib/idempotent-request/policy.rb
module IdempotentRequest
  class Policy
    attr_reader :request

    def initialize(request)
      @request = request
    end

    def should?
      # Custom logic to 
    end
  end
end
```

### Storage

Where the response will be stored. Can be any class that implements the following interface:

```ruby
def read(key)
  # read from a storage
end

def write(key, payload)
  # write to a storage
end
```

### Callback

Get notified when a client sends a request with the same idempotency key:

```ruby
class RailsCallback
  attr_reader :request

  def initialize(request)
    @request = request
  end

  def detected(key:)
    Rails.logger.warn "IdempotentRequest request detected, key: #{key}"
  end
end
```

### Use ActiveSupport::Notifications to read events

```ruby
# config/initializers/idempotent_request.rb
ActiveSupport::Notifications.subscribe('idempotent.request') do |name, start, finish, request_id, payload|
  notification = payload[:request].env['idempotent.request']
  if notification['read']
    Rails.logger.info "IdempotentRequest: Hit cached response from key #{notification['key']}, response: #{notification['read']}"
  elsif notification['write']
    Rails.logger.info "IdempotentRequest: Write: key #{notification['key']}, status: #{notification['write'][0]}, headers: #{notification['write'][1]}, unlocked? #{notification['unlocked']}"
  elsif notification['concurrent_request_response']
    Rails.logger.warn "IdempotentRequest: Concurrent request detected with key #{notification['key']}"
  end
end
```

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

## Releasing

To publish a new version to rubygems, update the version in `lib/version.rb`, and merge.
