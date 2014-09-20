require "excon"

module Excon
  module Middleware
    module AWS
      class ExponentialBackoff < Excon::Middleware::Base
        VERSION = "0.0.2"
      end
    end
  end
end
