source "https://rubygems.org"

plugin "bundler-inject", "~> 2.0"
require File.join(Bundler::Plugin.index.load_paths("bundler-inject")[0], "bundler-inject") rescue nil

# Specify your gem's dependencies in inventory_refresh.gemspec
gemspec

minimum_version =
  case ENV['TEST_RAILS_VERSION']
  when "7.2"
    "~>7.2.1"
  when "7.1"
    "~>7.1.4"
  else
    "~>7.0.8"
  end

gem "activerecord", minimum_version
