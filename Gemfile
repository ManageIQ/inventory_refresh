source "https://rubygems.org"

git_source(:github) {|repo_name| "https://github.com/#{repo_name}" }

# Specify your gem's dependencies in inventory_refresh.gemspec
gemspec

# Load other additional Gemfiles
#   Developers can create a file ending in .rb under bundler.d/ to specify additional development dependencies
Dir.glob(File.join(__dir__, 'bundler.d/*.rb')).each { |f| eval_gemfile(File.expand_path(f, __dir__)) }
