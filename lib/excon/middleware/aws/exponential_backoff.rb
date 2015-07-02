require 'excon'
require "excon/middleware/aws/exponential_backoff/version"

module Excon
  module Middleware
    module AWS
      class ExponentialBackoff < Excon::Middleware::Base
        MILLISECOND            = 1.0/1000
        SLEEP_FACTOR           = MILLISECOND * 100
        ERROR_REGEX            = [
                                  Regexp.new(/<Code>([^<]+)<\/Code>.*<Message>([^<]+)<\/Message>/mi),
                                  Regexp.new(/<Exception>([^<]+)<\/Exception>.*<Message>([^<]+)<\/Message>/mi),
                                  Regexp.new(/"__type":"([^"]+).*"message":"([^"]+)/mi)
                                 ]
        THROTTLING_ERROR_CODES = %w[
                                   Throttling
                                   ThrottlingException
                                   ProvisionedThroughputExceededException
                                   RequestThrottled
                                   RequestLimitExceeded
                                   BandwidthLimitExceeded
                                 ]
        SERVER_ERROR_CLASSES   = [
                                  Excon::Errors::ServerError,
                                  Excon::Errors::SocketError,
                                 ]
        VALID_MIDDLEWARE_KEYS =  [
                                  :backoff
                                 ]

        def self.append_keys(const_name, keys)
          new_value = (Excon.const_get(const_name) + keys).uniq
          Excon.send(:remove_const, const_name)
          Excon.const_set(const_name, new_value)
        end

        # Call methods during class definition
        append_keys("VALID_REQUEST_KEYS", VALID_MIDDLEWARE_KEYS)
        append_keys("VALID_CONNECTION_KEYS", VALID_MIDDLEWARE_KEYS)

        def self.defaults
          {
           :max_retries   => 0,
           :max_delay     => 30,
           :min_delay     => 0,
           :retry_count   => 0,
           :error_code    => nil,
           :error_message => nil,
           :original_request_start => nil
          }
        end

        def defaults
          self.class.defaults
        end

        Excon.defaults[:backoff] = defaults

        def request_call(datum)
          datum[:backoff] = (datum[:backoff] ||= {}).dup
          datum[:backoff][:error_code] = nil
          datum[:backoff][:error_message] = nil
          datum[:backoff][:original_request_start] ||= Time.now
          super
        end

        def response_call(datum)
          super
        end

        def error_call(datum)
          datum[:backoff] = defaults.merge(datum[:backoff] || {})
          if (throttle?(datum) || server_error?(datum)) && should_retry?(datum)
            do_backoff(datum)
          else
            do_handoff(datum)
          end
        end

        def do_handoff(datum)
          @stack.error_call(datum)
        end

        def do_backoff(datum)
          do_sleep(sleep_time(datum), datum)
          datum[:backoff][:retry_count] += 1
          connection = datum.delete(:connection)
          datum.reject! { |key, _| !(Excon::VALID_REQUEST_KEYS).include?(key) }
          connection.request(datum)
        end

        def do_sleep(sleep_time, datum)
          if datum.has_key?(:instrumentor)
            datum[:instrumentor].instrument("#{datum[:instrumentor_name]}.backoff", datum) do
              sleep sleep_time
            end
          else
            sleep sleep_time
          end
        end

        def sleep_time(datum)
          exponential_wait = (2 ** datum[:backoff][:retry_count] + rand(0.0)) * SLEEP_FACTOR
          max_delay = [
                       exponential_wait,
                       datum[:backoff][:max_delay]
                      ].min

          [
           max_delay,
           datum[:backoff][:min_delay]
          ].max.round(2)
        end

        def should_retry?(datum)
          # Always retry if max_retries is 0.
          datum[:backoff][:max_retries] == 0 ||
            datum[:backoff][:retry_count] < datum[:backoff][:max_retries]
        end

        def throttle?(datum)
          if datum[:error].kind_of?(Excon::Errors::BadRequest)
            code, message = extract_error_code_and_message(datum[:error].response.body)
            datum[:backoff][:error_code] = code
            datum[:backoff][:error_message] = message
            THROTTLING_ERROR_CODES.include?(code)
          end
        end

        def server_error?(datum)
          SERVER_ERROR_CLASSES.any? { |ex| datum[:error].kind_of?(ex) }
        end

        def extract_error_code_and_message(body)
          ERROR_REGEX.each{|regex|
            match = regex.match(body)
            if match
              return [match[1].strip, match[2].strip]
            end
          }
          nil
        end
      end
    end
  end
end
