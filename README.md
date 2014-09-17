# Excon::Middleware::Aws::ExponentialBackoff

Excon middleware to exponentially backoff calling AWS APIs when throttled or experiencing errors.

## Installation

Add this line to your application's Gemfile:

    gem 'excon-middleware-aws-exponential_backoff'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install excon-middleware-aws-exponential_backoff

## Usage

This gem is intended to be used with fog and excon when communicating with AWS APIs.

```ruby
require "fog"
require "excon/middleware/aws/exponential_backoff"

Excon.defaults[:middlewares] << Excon::Middleware::AWS::ExponentialBackoff

10.times do
  p Fog::DNS::AWS.new(aws_access_key_id: 'key', aws_secret_access_key: 'secret').list_hosted_zones
end
```

## Contributing

1. Fork it ( https://github.com/[my-github-username]/excon-middleware-aws-exponential_backoff/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
