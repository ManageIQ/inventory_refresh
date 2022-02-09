lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "inventory_refresh/version"

Gem::Specification.new do |spec|
  spec.name          = "inventory_refresh"
  spec.version       = InventoryRefresh::VERSION
  spec.authors       = ["ManageIQ Developers"]

  spec.summary       = 'Topological Inventory Persister'
  spec.description   = 'Topological Inventory Persister'
  spec.homepage      = "https://github.com/ManageIQ/inventory_refresh"
  spec.licenses      = ["Apache-2.0"]

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.add_dependency "activerecord", ">=5.0", "< 7.0"
  spec.add_dependency "more_core_extensions", ">=3.5", "< 5"
  spec.add_dependency "pg", "> 0"

  spec.add_development_dependency "ancestry"
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "factory_bot", "~> 4.11.1"
  spec.add_development_dependency "manageiq-style"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "simplecov", ">= 0.21.2"
end
