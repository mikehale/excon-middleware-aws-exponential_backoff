require "excon/middleware/aws/exponential_backoff"

if (index = Excon.defaults[:middlewares].index(Excon::Middleware::Instrumentor))
  Excon.defaults[:middlewares].insert(index, Excon::Middleware::AWS::ExponentialBackoff)
else
  Excon.defaults[:middlewares] << Excon::Middleware::AWS::ExponentialBackoff
end
