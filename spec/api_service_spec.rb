require 'spec_helper'

describe GoCardlessPro::ApiService do
  subject(:service) { described_class.new('https://api.example.com', 'secret_token') }

  it 'uses basic auth' do
    stub = stub_request(:get, 'https://api.example.com/customers')
           .with(headers: { 'Authorization' => 'Bearer secret_token' })
    service.make_request(:get, '/customers')
    expect(stub).to have_been_requested
  end

  describe 'making a get request without any parameters' do
    it 'is expected to call the correct stub' do
      stub = stub_request(:get, /.*api.example.com\/customers/)
      service.make_request(:get, '/customers')
      expect(stub).to have_been_requested
    end

    it "doesn't include an idempotency key" do
      stub = stub_request(:get, /.*api.example.com\/customers/)
             .with { |request| !request.headers.key?('Idempotency-Key') }
      service.make_request(:get, '/customers')
      expect(stub).to have_been_requested
    end
  end

  describe 'making a get request with query parameters' do
    it 'correctly passes the query parameters' do
      stub = stub_request(:get, /.*api.example.com\/customers\?a=1&b=2/)
      service.make_request(:get, '/customers', params: { a: 1, b: 2 })
      expect(stub).to have_been_requested
    end

    it "doesn't include an idempotency key" do
      stub = stub_request(:get, /.*api.example.com\/customers\?a=1&b=2/)
             .with { |request| !request.headers.key?('Idempotency-Key') }
      service.make_request(:get, '/customers', params: { a: 1, b: 2 })
      expect(stub).to have_been_requested
    end
  end

  describe 'making a post request with some data' do
    it 'passes the data in as the post body' do
      stub = stub_request(:post, /.*api.example.com\/customers/)
             .with(body: { given_name: 'Jack', family_name: 'Franklin' })
      service.make_request(:post, '/customers', params: {
                             given_name: 'Jack',
                             family_name: 'Franklin'
                           })
      expect(stub).to have_been_requested
    end

    it 'generates a random idempotency key' do
      allow(SecureRandom).to receive(:uuid).and_return('random-uuid')

      stub = stub_request(:post, /.*api.example.com\/customers/)
             .with(
               body: { given_name: 'Jack', family_name: 'Franklin' },
               headers: { 'Idempotency-Key' => 'random-uuid' }
             )

      service.make_request(:post, '/customers', params: {
                             given_name: 'Jack',
                             family_name: 'Franklin'
                           })
      expect(stub).to have_been_requested
    end
  end

  describe 'making a post request with data and custom header' do
    it 'passes the data in as the post body' do
      stub = stub_request(:post, /.*api.example.com\/customers/)
             .with(
               body: { given_name: 'Jack', family_name: 'Franklin' },
               headers: { 'Foo' => 'Bar' }
             )

      service.make_request(:post, '/customers', params: {
                             given_name: 'Jack',
                             family_name: 'Franklin'
                           },
                                                headers: {
                                                  'Foo' => 'Bar'
                                                })
      expect(stub).to have_been_requested
    end

    it 'merges in a random idempotency key' do
      allow(SecureRandom).to receive(:uuid).and_return('random-uuid')

      stub = stub_request(:post, /.*api.example.com\/customers/)
             .with(
               body: { given_name: 'Jack', family_name: 'Franklin' },
               headers: { 'Idempotency-Key' => 'random-uuid', 'Foo' => 'Bar' }
             )

      service.make_request(:post, '/customers', params: {
                             given_name: 'Jack',
                             family_name: 'Franklin'
                           },
                                                headers: {
                                                  'Foo' => 'Bar'
                                                })
      expect(stub).to have_been_requested
    end

    context 'with a custom idempotency key' do
      it "doesn't replace it with a randomly-generated idempotency key" do
        stub = stub_request(:post, /.*api.example.com\/customers/)
               .with(
                 body: { given_name: 'Jack', family_name: 'Franklin' },
                 headers: { 'Idempotency-Key' => 'my-custom-idempotency-key' }
               )

        service.make_request(:post, '/customers', params: {
                               given_name: 'Jack',
                               family_name: 'Franklin'
                             },
                                                  headers: {
                                                    'Idempotency-Key' => 'my-custom-idempotency-key'
                                                  })
        expect(stub).to have_been_requested
      end
    end
  end

  describe 'making a put request with some data' do
    it 'passes the data in as the request body' do
      stub = stub_request(:put, /.*api.example.com\/customers\/CU123/)
             .with(body: { given_name: 'Jack', family_name: 'Franklin' })
      service.make_request(:put, '/customers/CU123', params: {
                             given_name: 'Jack',
                             family_name: 'Franklin'
                           })
      expect(stub).to have_been_requested
    end

    it "doesn't include an idempotency key" do
      stub = stub_request(:put, /.*api.example.com\/customers\/CU123/)
             .with { |request| !request.headers.key?('Idempotency-Key') }

      service.make_request(:put, '/customers/CU123', params: {
                             given_name: 'Jack',
                             family_name: 'Franklin'
                           })
      expect(stub).to have_been_requested
    end
  end

  describe 'timeout retry behaviour' do
    context 'for a GET request' do
      it 'retries timeouts' do
        stub = stub_request(:get, /.*api.example.com\/customers/).to_timeout
               .then.to_return(status: 200)

        service.make_request(:get, '/customers')
        expect(stub).to have_been_requested.twice
      end
    end

    context 'for a PUT request' do
      it 'retries timeouts' do
        stub = stub_request(:put, /.*api.example.com\/creditors\/CR123/).to_timeout
               .then.to_return(status: 200)

        service.make_request(:put, '/creditors/CR123', params: { creditors: { name: 'Acme plc' } })
        expect(stub).to have_been_requested.twice
      end
    end

    context 'for a POST request' do
      context 'creating a resource' do
        it 'retries the request' do
          stub = stub_request(:post, /.*api.example.com\/customers/).to_timeout
                 .then.to_return(status: 200)

          service.make_request(:post, '/customers', params: { customers: { given_name: 'Tim' } })
          expect(stub).to have_been_requested.twice
        end
      end

      context 'performing an action on a resource' do
        it "doesn't retry request" do
          stub = stub_request(:post, /.*api.example.com\/payments\/PM123\/actions\/cancel/).to_timeout

          expect { service.make_request(:post, '/payments/PM123/actions/cancel') }
            .to raise_error(Faraday::TimeoutError)
          expect(stub).to have_been_requested
        end
      end
    end
  end
end
