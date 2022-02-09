source "https://rubygems.org"

plugin "bundler-inject", "~> 2.0"
require File.join(Bundler::Plugin.index.load_paths("bundler-inject")[0], "bundler-inject") rescue nil

# Specify your gem's dependencies in inventory_refresh.gemspec
gemspec

case ENV['TEST_RAILS_VERSION']
when "5.2"
  gem "activerecord", "~>5.2.6"
when "6.0"
  gem "activerecord", "~>6.0.4"
when "6.1"
  gem "activerecord", "~>6.1.4"
end
