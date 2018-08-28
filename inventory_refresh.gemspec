$:.push File.expand_path("../lib", __FILE__)

require "inventory_refresh/version"

Gem::Specification.new do |s|
  s.name        = "inventory_refresh"
  s.version     = InventoryRefresh::VERSION
  s.authors     = ["ManageIQ Developers"]
  s.homepage    = "https://github.com/ManageIQ/inventory_refresh"
  s.summary     = "Topological Inventory Persister"
  s.description = "Topological Inventory Persister"
  s.licenses    = ["Apache-2.0"]

  s.files = Dir["{app,config,lib}/**/*"]

  s.add_dependency "activesupport", "~> 5.0.6"

  s.add_development_dependency "bundler"
  s.add_development_dependency "rake"
  s.add_development_dependency "rspec", "~> 3.0"
  s.add_development_dependency "simplecov"
  s.add_development_dependency "codeclimate-test-reporter", "~> 1.0.0"
end
