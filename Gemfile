source 'https://rubygems.org'

gemspec

# CI also runs the specs with Faraday 1, which fastlane used before 2.238.0
faraday_version = ENV.fetch("FARADAY_VERSION", "")
gem "faraday", faraday_version unless faraday_version.empty?
# Without a pin, Bundler picks a fastlane too old to load on current Ruby
fastlane_version = ENV.fetch("FASTLANE_VERSION", "")
gem "fastlane", fastlane_version unless fastlane_version.empty?

plugins_path = File.join(File.dirname(__FILE__), 'fastlane', 'Pluginfile')
eval_gemfile(plugins_path) if File.exist?(plugins_path)
