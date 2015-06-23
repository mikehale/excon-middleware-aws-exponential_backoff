require "spec_helper"

class Stack
  def error_call(datum); end
  def request_call(datum); end
  def response_call(datum); end
end

class Instrumentor
  def instrument(name, datum, &block)
    return unless block
    block.call
  end
end

RSpec.describe Excon::Middleware::AWS::ExponentialBackoff do
  let(:stack) { Stack.new }
  subject { Excon::Middleware::AWS::ExponentialBackoff.new(stack) }

  it "detects errors in json responses" do
    expect(subject.extract_error_code('{"__type":"ProvisionedThroughputExceededException","message":"Rate exceeded"')).to eq "ProvisionedThroughputExceededException"
  end

  it "detects errors in xml responses" do
    expect(subject.extract_error_code('<Code>ProvisionedThroughputExceededException</Code>')).to eq "ProvisionedThroughputExceededException"
  end

  it { is_expected.to respond_to :error_call }

  it "delays exponentially longer" do
    wait1 = subject.sleep_time(backoff: {max_delay: 10, retry_count: 0 })
    wait2 = subject.sleep_time(backoff: {max_delay: 10, retry_count: 1 })
    wait3 = subject.sleep_time(backoff: {max_delay: 10, retry_count: 2 })
    expect(wait3).to be > wait2
    expect(wait2).to be > wait1
    expect(wait1).to be > 0
  end

  it "should not exceed max_delay" do
    expect(subject.sleep_time(backoff: {max_delay: 1, retry_count: 10 })).to be 1.0
  end

  it "always retries if max_retries is 0" do
    expect(subject.should_retry?(backoff: {max_retries: 0})).to be true
  end

  it "retries if retry_count is < max_retries" do
    expect(subject.should_retry?(backoff: {retry_count:0, max_retries: 1})).to be true
    expect(subject.should_retry?(backoff: {retry_count:1, max_retries: 1})).to be false
  end

  it "backs off when throttled" do
    throttled = Excon::Errors.status_error({}, throttling_response)
    redirect = Excon::Errors.status_error({}, Excon::Response.new(status: 302))
    bad_request = Excon::Errors.status_error({}, Excon::Response.new(status: 400))

    expect(subject.throttle?(error: throttled)).to be true
    expect(subject.throttle?(error: redirect)).to be false
    expect(subject.throttle?(error: bad_request)).to be false
  end

  it "backs off when there is a server error" do
    expect(subject.server_error?(error: Excon::Errors.status_error({}, Excon::Response.new(status: 500)))).to be true
    expect(subject.server_error?(error: Excon::Errors.status_error({}, Excon::Response.new(status: 501)))).to be false
    expect(subject.server_error?(error: Excon::Errors.status_error({}, Excon::Response.new(status: 502)))).to be true
    expect(subject.server_error?(error: Excon::Errors.status_error({}, Excon::Response.new(status: 503)))).to be true
    expect(subject.server_error?(error: Excon::Errors.status_error({}, Excon::Response.new(status: 504)))).to be true
  end

  it "should call do_backoff when throttled" do
    throttled = Excon::Errors.status_error({}, throttling_response)
    expect(subject).to receive(:do_backoff)
    subject.error_call(error: throttled)
  end

  it "should call do_handoff when not throttled" do
    bad_request = Excon::Errors.status_error({}, Excon::Response.new(status: 400))
    expect(subject).to receive(:do_handoff)
    subject.error_call(error: bad_request)
  end

  it "hands off correctly" do
    datum = {}
    expect(stack).to receive(:error_call).with(datum)
    subject.do_handoff(datum)
  end

  it "can be instrumented" do
    instrumentor = Instrumentor.new
    error = instance_double("HTTPStatusError")
    allow(error).to receive(:response) { "The Response" }

    datum = {
             instrumentor: instrumentor,
             instrumentor_name: "test",
             error: error
            }

    expect(instrumentor).to receive(:instrument).with("test.backoff", datum).and_call_original
    expect_any_instance_of(Kernel).to receive(:sleep)
    subject.do_sleep(0, datum)
  end

  it "works when not instrumented" do
    error = instance_double("HTTPStatusError")
    allow(error).to receive(:response) { "The Response" }

    expect_any_instance_of(Kernel).to receive(:sleep)
    subject.do_sleep(0, { error: error })
  end

  context :do_backoff do
    let(:connection) { double("connection") }
    let(:datum) {
      {
       backoff: {
                 retry_count: 1,
                 max_delay: 10
                },
       connection: connection
      }
    }

    before do
      allow(connection).to receive(:request)
      allow(subject).to receive(:do_sleep)
    end

    it "increments the request_count" do
      subject.do_backoff(datum)
      expect(datum[:backoff][:retry_count]).to be 2
    end

    it "restarts request call with a reset connection" do
      expect(connection).to receive(:request).with({backoff: {max_delay: 10, retry_count: 2}})
      subject.do_backoff(datum.merge(ignored_stuff: :foo))
    end

    it "sleeps for the specified time" do
      allow(subject).to receive(:sleep_time) { 1.1 }
      expect(subject).to receive(:do_sleep).with(1.1, datum)
      subject.do_backoff(datum)
    end
  end

  it "should work against a real server" do
    Excon.defaults[:mock] = false
    Excon.defaults[:middlewares] << Excon::Middleware::AWS::ExponentialBackoff

    datum = {
             instrumentor: Instrumentor.new,
             instrumentor_name: "test",
             expects: [200],
             backoff: {
                       max_retries: 3,
                       max_delay: 0
                      }
            }

    ServerHelper.with_server("aws") do
      expect(Excon.get('http://127.0.0.1:9292/throttle/3', datum).body).to eq "OK"
    end
  end

  it "should include :backoff in Excon::VALID_REQUEST_KEYS" do
    expect(Excon::VALID_REQUEST_KEYS).to include(:backoff)
  end

  it "should include :backoff in Excon::VALID_CONNECTION_KEYS" do
    expect(Excon::VALID_CONNECTION_KEYS).to include(:backoff)
  end
end
