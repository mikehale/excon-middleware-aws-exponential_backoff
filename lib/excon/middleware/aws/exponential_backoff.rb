require 'excon'
require "excon/middleware/aws/exponential_backoff/version"

module Excon
  module Middleware
    module AWS
      class ExponentialBackoff < Excon::Middleware::Base
        MILLISECOND            = 1.0/1000
        SLEEP_FACTOR           = MILLISECOND * 100
        ERROR_CODE_REGEX       = Regexp.new(/<Code>([^<]+)<\/Code>/mi)
        THROTTLING_ERROR_CODES = %w[
                                   Throttling
                                   ThrottlingException
                                   ProvisionedThroughputExceededException
                                   RequestThrottled
                                   RequestLimitExceeded
                                   BandwidthLimitExceeded
        ]
        SERVER_ERROR_CLASSES   = [
                                  Excon::Errors::InternalServerError,
                                  Excon::Errors::BadGateway,
                                  Excon::Errors::ServiceUnavailable,
                                  Excon::Errors::GatewayTimeout
                                 ]
        VALID_MIDDLEWARE_KEYS = [
                                 :backoff
                                ]

        def self.append_valid_request_keys
          new_value = (Excon::VALID_REQUEST_KEYS + VALID_MIDDLEWARE_KEYS).uniq
          Excon.send(:remove_const, "VALID_REQUEST_KEYS")
          Excon.const_set("VALID_REQUEST_KEYS", new_value)
        end

        # Call method during class definition
        append_valid_request_keys

        def error_call(datum)
          datum[:backoff] ||= {}
          datum[:backoff][:max_retries] ||= 0
          datum[:backoff][:max_delay]   ||= 30
          datum[:backoff][:retry_count] ||= 0

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
          datum.reject! { |key, _| !(Excon::VALID_REQUEST_KEYS).include?(key)  }
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
          [
           exponential_wait, 
           datum[:backoff][:max_delay]
          ].min.round(2)
        end

        def should_retry?(datum)
          # Always retry if max_retries is 0.
          datum[:backoff][:max_retries] == 0 ||
            datum[:backoff][:retry_count] < datum[:backoff][:max_retries]
        end

        def throttle?(datum)
          datum[:error].kind_of?(Excon::Errors::BadRequest) &&
            THROTTLING_ERROR_CODES.include?(extract_error_code(datum[:error].response.body))
        end

        def server_error?(datum)
          SERVER_ERROR_CLASSES.any? { |ex| datum[:error].kind_of?(ex) }
        end

        def extract_error_code(body)
          match = ERROR_CODE_REGEX.match(body)
          if match && code = match[1]
            code.strip if code
          end
        end
      end
    end
  end
end
