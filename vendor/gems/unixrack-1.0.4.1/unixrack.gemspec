# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'unixrack/version'

Gem::Specification.new do |spec|
  spec.name          = "unixrack"
  spec.version       = Unixrack::VERSION
  spec.authors       = ["Dru Nelson"]
  spec.email         = ["drudru@gmail.com"]
  spec.description   = %q{Simple Rack Compatible Web Server in Ruby}
  spec.summary       = %q{Old School Super Solid Forking Web Server for Ruby}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "rack", "~> 1.5"

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
end
