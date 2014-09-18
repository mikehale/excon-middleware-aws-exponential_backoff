require "spec_helper"

class Stack
  def error_call(datum); end
  def request_call(datum); end
  def response_call(datum); end
end

class Instrumentor
  def instrument(msg, datum, &block)
    block.call if block
  end
end

RSpec.describe Excon::Middleware::AWS::ExponentialBackoff do
  let(:stack) { Stack.new }
  subject { Excon::Middleware::AWS::ExponentialBackoff.new(stack) }

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
    datum = {
             instrumentor: instrumentor,
             instrumentor_name: "test"
            }

    expect(instrumentor).to receive(:instrument).with("test.backoff", datum).and_call_original
    expect_any_instance_of(Kernel).to receive(:sleep)
    subject.do_sleep(0, datum)
  end

  it "works when not instrumented" do
    expect_any_instance_of(Kernel).to receive(:sleep)
    subject.do_sleep(0, {})
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
end
