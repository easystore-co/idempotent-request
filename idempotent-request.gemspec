# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'version'

Gem::Specification.new do |spec|
  spec.name          = 'idempotent-request'
  spec.version       = IdempotentRequest::VERSION
  spec.authors       = ['Dmytro Zakharov']
  spec.email         = ['dmytro@qonto.eu']

  spec.summary       = %q{Rack middleware ensuring at most once requests for mutating endpoints.}
  spec.homepage      = 'https://github.com/qonto/idempotent-request'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'rack', '~> 3.0'
  spec.add_dependency 'oj', '~> 3.0'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rake', '>= 12.3.3'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'fakeredis', '~> 0.6'
  spec.add_development_dependency 'byebug', '>= 11.1.3'
end
