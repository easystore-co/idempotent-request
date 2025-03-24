require 'spec_helper'

RSpec.describe IdempotentRequest::Middleware do
  let(:app) { -> (env) { [200, {}, 'body'] } }
  let(:env) do
    env_for('https://qonto.eu', method: 'POST')
      .merge!(
        'HTTP_IDEMPOTENCY_KEY' => 'dont-repeat-this-request-pls'
      )
  end
  let(:storage) { @memory_storage ||= IdempotentRequest::MemoryStorage.new }
  let(:policy) do
    class_double('IdempotentRequest::policy', new: double(should?: true))
  end
  let(:config_file) { 'spec/support/idempotent.yml' }

  let(:middleware) do
    described_class.new(app,
      policy: policy,
      storage: storage,
      config_file: config_file
    )
  end

  context 'when should be idempotent' do
    it 'should be saved to storage' do
      expect_any_instance_of(IdempotentRequest::RequestManager).to receive(:read)
      expect_any_instance_of(IdempotentRequest::RequestManager).to receive(:write)

      middleware.call(env)
    end

    it 'should obtain lock and release lock' do
      expect_any_instance_of(IdempotentRequest::RequestManager).to receive(:lock).and_return(true)
      expect_any_instance_of(IdempotentRequest::RequestManager).to receive(:write)
      expect_any_instance_of(IdempotentRequest::RequestManager).to receive(:unlock)

      middleware.call(env)
    end

    context 'when an exception happens inside another middleware' do
      let(:app) { ->(_) { raise 'fatality' } }

      it 'should release lock' do
        expect_any_instance_of(IdempotentRequest::RequestManager).to receive(:lock).and_return(true)
        expect_any_instance_of(IdempotentRequest::RequestManager).not_to receive(:write)
        expect_any_instance_of(IdempotentRequest::RequestManager).to receive(:unlock)

        expect { middleware.call(env) }.to raise_error('fatality')
      end
    end

    context 'when has data in storage' do
      before do
        data = [200, {}, 'body']
        allow_any_instance_of(IdempotentRequest::RequestManager).to receive(:read).and_return(data)
      end

      it 'should read from storage' do
        expect_any_instance_of(IdempotentRequest::RequestManager).to receive(:read)
        expect_any_instance_of(IdempotentRequest::RequestManager).not_to receive(:write)

        middleware.call(env)
      end
    end

    context 'when concurrent requests' do
      before do
        allow_any_instance_of(IdempotentRequest::RequestManager).to receive(:lock).and_return(false)
      end

      it 'should not return data from storage' do
        expect_any_instance_of(IdempotentRequest::RequestManager).to receive(:read).and_return(nil)

        middleware.call(env)
      end

      it 'should not obtain lock' do
        expect_any_instance_of(IdempotentRequest::RequestManager).not_to receive(:write)

        middleware.call(env)
      end

      it 'returns 429 status' do
        status, _headers, _body = middleware.call(env)

        expect(status).to be(429)
      end

      context 'when custom response status is set' do
        let(:config_file) { 'spec/support/idempotent_custom_response_status.yml' }

        it 'returns 409 status' do
          status, _headers, _body = middleware.call(env)

          expect(status).to be(409)
        end
      end
    end
  end

  context 'when should not be idempotent' do
    let(:policy) do
      class_double('IdempotentRequest::policy', new: double(should?: false))
    end

    it 'should not read storage' do
      expect_any_instance_of(IdempotentRequest::RequestManager).not_to receive(:read)
      expect_any_instance_of(IdempotentRequest::RequestManager).not_to receive(:write)

      middleware.call(env)
    end
  end
end
