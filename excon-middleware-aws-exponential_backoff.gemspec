# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'excon/middleware/aws/exponential_backoff/version'

Gem::Specification.new do |spec|
  spec.name          = "excon-middleware-aws-exponential_backoff"
  spec.version       = Excon::Middleware::Aws::ExponentialBackoff::VERSION
  spec.authors       = ["Michael Hale"]
  spec.email         = ["mike@hales.ws"]
  spec.summary       = %q{Excon middleware to exponentially backoff calling AWS APIs when throttled or experiencing errors.}
  spec.homepage      = "https://github.com/mikehale/excon-middleware-aws-exponential_backoff"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_dependency "excon"
end
