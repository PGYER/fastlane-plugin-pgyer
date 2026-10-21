$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require "simplecov"

# SimpleCov.minimum_coverage 95
SimpleCov.start

# This module is only used to check the environment is currently a testing env
module SpecHelper
end

require "fastlane" # to import the Action super class
require "fastlane/plugin/pgyer" # import the actual plugin
require "webmock/rspec"
require "tmpdir"

Fastlane.load_actions # load other actions (in case your plugin calls other actions or shared values)

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |file| require(file) }

WebMock.disable_net_connect!

RSpec.configure do |config|
  config.include(PgyerSpecSupport)

  config.before do
    Fastlane::Actions.lane_context.clear
    PgyerSpecSupport.requests.clear
  end
end
