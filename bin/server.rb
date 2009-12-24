#!/usr/bin/ruby

Dir.glob(File.join("gems", "gems", "*", "lib")).each do |lib|
  $LOAD_PATH.unshift(File.expand_path(lib))
end

require 'rubygems'
gem_paths = [File.expand_path(File.join("gems")),  Gem.default_dir]
Gem.clear_paths
Gem.send :set_paths, gem_paths.join(":")

require 'code/router.rb'

builder = MiniRouter.new

Rack::Handler::WEBrick.run(builder, :Port => 3333)
