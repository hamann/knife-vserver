# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'knife-vserver/version'

Gem::Specification.new do |spec|
  spec.name          = "knife-vserver"
  spec.version       = Knife::Vserver::VERSION
  spec.authors       = ["Holger Amann"]
  spec.email         = ["holger@fehu.org"]
  spec.description   = %q{A plugin for chef's knife to manage Linux VServers}
  spec.summary       = %q{A plugin for chef's knife to manage Linux VServers}
  spec.homepage      = "https://github.com/hamann/knife-vserver"
  spec.license       = "Apache 2.0"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency 'chef', '>= 10.0'

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
end
