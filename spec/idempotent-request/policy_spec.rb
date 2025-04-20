require 'spec_helper'

RSpec.describe IdempotentRequest::Policy do
  let(:url) { 'https://qonto.eu' }
  let(:default_env) { env_for(url) }
  let(:env) { default_env }
  let(:request) { IdempotentRequest::Request.new(env) }
  let(:expire_time) { 3600 }
  let(:routes) {
    [
      {
        path: '/api/v1/test/*',
        http_method: 'POST',
        expire_time: 180
      },
      {
        path: '/api/v2/test/*',
        http_method: 'POST',
        expire_time: 180
      },
      {
        path: '/admin/v2/store/orders',
        http_method: 'POST',
        expire_time: 180
      }
    ]
  }
  let(:policy) { described_class.new(request, { routes: routes, expire_time: expire_time }) }

  describe '#should?' do
    subject { policy.should? }

    context 'when the request matches a route' do
      let(:env) { default_env.merge('PATH_INFO' => '/api/v1/test/123', 'REQUEST_METHOD' => 'POST') }

      it { is_expected.to be_truthy }
    end

    context 'when the request matches a route with trailing slash' do
      let(:env) { default_env.merge('PATH_INFO' => '/admin/v2/store/orders/', 'REQUEST_METHOD' => 'POST') }

      it { is_expected.to be_truthy }
    end

    context 'when the route has a trailing slash and the request does not' do
      let(:routes) {
        [
          {
            path: '/admin/v2/store/products/',
            http_method: 'POST',
            expire_time: 180
          }
        ]
      }
      let(:env) { default_env.merge('PATH_INFO' => '/admin/v2/store/products', 'REQUEST_METHOD' => 'POST') }

      it { is_expected.to be_truthy }
    end

    context 'when the request does not match a route due to path' do
      let(:env) { default_env.merge('PATH_INFO' => '/api/v1/other') }

      it { is_expected.to be_falsey }
    end

    context 'when the request does not match a route due to method' do
      let(:env) { default_env.merge('PATH_INFO' => '/api/v1/test/123', 'REQUEST_METHOD' => 'GET') }

      it { is_expected.to be_falsey }
    end
  end

  describe '#expire_time_for_request' do
    subject { policy.expire_time_for_request }

    context 'when the request matches a route' do
      let(:env) { default_env.merge('PATH_INFO' => '/api/v1/test/123', 'REQUEST_METHOD' => 'POST') }

      it { is_expected.to eq(180) }
    end

    context 'when the request matches a route with trailing slash' do
      let(:env) { default_env.merge('PATH_INFO' => '/admin/v2/store/orders/', 'REQUEST_METHOD' => 'POST') }

      it { is_expected.to eq(180) }
    end

    context 'when the request does not match a route' do
      let(:env) { default_env.merge('PATH_INFO' => '/api/v1/other') }

      it { is_expected.to eq(3600) }
    end
  end
end
