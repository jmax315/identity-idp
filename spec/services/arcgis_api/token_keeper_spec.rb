# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ArcgisApi::TokenKeeper do
  # Faraday::Connection object that uses the test adapter
  let(:connection_factory) { ArcgisApi::ConnectionFactory.new }
  let(:prefetch_ttl) { 1 }
  let(:analytics) { instance_spy(Analytics) }
  let(:subject) do
    obj = described_class.new(
      cache_key: 'test_arcgis_api_token',
      connection_factory: connection_factory, prefetch_ttl: prefetch_ttl
    )
    obj.analytics = (analytics)
    obj
  end

  let(:expected) { 'ABCDEFG' }
  let(:expected_sec) { 'GFEDCBA' }
  let(:expires_at) { (Time.zone.now.to_f + 15) * 1000 }
  let(:cache) { Rails.cache }
  # before do
  #   allow(Rails).to receive(:cache).and_return(cache_store)
  # end

  before(:each) do
    allow(Rails).to receive(:cache).and_return(cache_store)
    subject.remove_token
  end

  shared_examples 'acquire token test' do
    context 'token not expired and not in prefetch timeframe' do
      it 'get same token at second call' do
        expected = 'ABCDEFG'
        expected_sec = 'GFEDCBA'

        stub_request(:post, %r{/generateToken}).to_return(
          { status: 200,
            body: {
              token: expected,
              expires: (Time.zone.now.to_f + 5) * 1000,
              ssl: true,
            }.to_json,
            headers: { content_type: 'application/json;charset=UTF-8' } },
          { status: 200,
            body: {
              token: expected_sec,
              expires: (Time.zone.now.to_f + 3600) * 1000,
              ssl: true,
            }.to_json,
            headers: { content_type: 'application/json;charset=UTF-8' } },
        )

        expect(Rails.cache).to receive(:read).with(kind_of(String)).
          and_call_original
        token = subject.token
        expect(token).to eq(expected)
        sleep(1)
        expect(Rails.cache).to receive(:read).with(kind_of(String)).
          and_call_original
        token = subject.token
        expect(token).to eq(expected)
      end
    end

    context 'token not expired and but in prefetch timeframe' do
      let(:expected) { 'ABCDEFG' }
      let(:expected_sec) { 'GFEDCBA' }
      before(:each) do
        stub_request(:post, %r{/generateToken}).to_return(
          { status: 200,
            body: {
              token: expected,
              expires: (Time.zone.now.to_f + 15) * 1000,
              ssl: true,
            }.to_json,
            headers: { content_type: 'application/json;charset=UTF-8' } },
          { status: 200,
            body: {
              token: expected_sec,
              expires: (Time.zone.now.to_f + 3600) * 1000,
              ssl: true,
            }.to_json,
            headers: { content_type: 'application/json;charset=UTF-8' } },
        )
      end
      let(:prefetch_ttl) do
        5
      end
      context 'get token at different timing' do
        it 'get same token between sliding_expires_at passed and sliding_expires_at+prefetch_ttl' do
          expect(Rails.cache).to receive(:read).with(kind_of(String)).
            and_call_original
          token = subject.token
          expect(token).to eq(expected)
          sleep(1)
          expect(Rails.cache).to receive(:read).with(kind_of(String)).
            and_call_original
          token = subject.token
          expect(token).to eq(expected)
        end
        it 'regenerates token when passed sliding_expires_at+prefetch_ttl' do
          expect(Rails.cache).to receive(:read).with(kind_of(String)).
            and_call_original
          token = subject.token
          expect(token).to eq(expected)
          sleep(11)
          expect(Rails.cache).to receive(:read).with(kind_of(String)).
            and_call_original
          token = subject.token
          expect(token).to eq(expected_sec)
        end
      end
    end

    context 'value only token in cache' do
      let(:expected) { 'ABCDEFG' }
      let(:expected_sec) { 'GFEDCBA' }
      before(:each) do
        stub_request(:post, %r{/generateToken}).to_return(
          { status: 200,
            body: {
              token: expected,
              expires: (Time.zone.now.to_f + 15) * 1000,
              ssl: true,
            }.to_json,
            headers: { content_type: 'application/json;charset=UTF-8' } },
        )
        subject.save_token(expected, expires_at)
      end
      let(:prefetch_ttl) do
        5
      end
      it 'should use deal with the value only token' do
        token = subject.token
        expect(token).to eq(expected)
      end
    end
  end
  context 'with in memory store' do
    let(:cache_store) { ActiveSupport::Cache.lookup_store(:memory_store) }
    context 'sliding expiration enabled' do
      before(:each) do
        allow(IdentityConfig.store).to receive(:arcgis_token_sliding_expiration_enabled).
          and_return(true)
      end
      include_examples 'acquire token test'
    end
  end
  context 'with redis store' do
    let(:cache_store) do
      ActiveSupport::Cache.lookup_store(:redis_cache_store, { url: IdentityConfig.store.redis_url })
    end
    include_examples 'acquire token test'
    context 'retry options' do
      it 'retry remote request multiple times as needed and emit analytics events' do
        stub_request(:post, %r{/generateToken}).to_return(
          {
            status: 503,
          },
          {
            status: 200,
            body: ArcgisApi::Mock::Fixtures.request_token_service_error,
            headers: { content_type: 'application/json;charset=UTF-8' },
          },
          {
            status: 200,
            body: ArcgisApi::Mock::Fixtures.invalid_gis_token_credentials_response,
            headers: { content_type: 'application/json;charset=UTF-8' },
          },
          { status: 200,
            body: {
              token: expected,
              expires: (Time.zone.now.to_f + 3600) * 1000,
              ssl: true,
            }.to_json,
            headers: { content_type: 'application/json;charset=UTF-8' } },
        )
        token = subject.retrieve_token
        expect(token&.token).to eq(expected)
        expect(analytics).to have_received(:idv_arcgis_token_failure).exactly(3).times
      end

      it 'raises exception after max retries and log event correctly' do
        allow(IdentityConfig.store).to receive(:arcgis_get_token_retry_max).and_return(2)
        stub_request(:post, %r{/generateToken}).to_return(
          {
            status: 503,
          },
          {
            status: 429,
          },
          {
            status: 504,
          },
        )
        expect do
          subject.retrieve_token
        end.to raise_error(Faraday::Error)

        msgs = []
        expect(analytics).to have_received(:idv_arcgis_token_failure) { |method_args|
          msg = method_args.fetch(:exception_message)
          msgs << msg
        }.exactly(2).times.ordered
        expect(msgs[0]).to match(/retry count/)
        expect(msgs[1]).to match(/max retries/)
      end
    end
    context 'token sync request disabled' do
      it 'does not fetch token' do
        allow(IdentityConfig.store).to receive(:arcgis_token_sync_request_enabled).
          and_return(false)
        expect(subject.token).to be(nil)
      end
    end
  end
end
