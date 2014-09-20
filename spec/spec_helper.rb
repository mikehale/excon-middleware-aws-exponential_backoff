require "excon/middleware/aws/exponential_backoff"

Dir[File.join(File.expand_path("../support", __FILE__), "**/*.rb")].each {|f| require f}

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  if config.files_to_run.one?
    config.default_formatter = 'doc'
  end
  config.disable_monkey_patching!
  config.warnings = true
  config.order = :random
  Kernel.srand config.seed

  config.include AWSErrorHelper

  config.around(:each) do |example|
    excon_defaults = Excon.defaults
    Excon.defaults[:mock] = true

    example.run

    Excon.defaults = excon_defaults
    Excon.stubs.clear
  end

  config.before(:all) do
    Excon.stub({}, {:body => 'Fallback', :status => 200})
  end
end
