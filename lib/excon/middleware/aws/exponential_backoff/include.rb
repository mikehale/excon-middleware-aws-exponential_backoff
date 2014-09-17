require "excon/middleware/aws/exponential_backoff"
Excon.defaults[:middlewares] << Excon::Middleware::AWS::ExponentialBackoff
