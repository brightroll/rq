#!/usr/bin/ruby

$:.unshift(File.join(File.dirname(__FILE__), ".."))

Dir.glob(File.join("gems", "gems", "*", "lib")).each do |lib|
  $LOAD_PATH.unshift(File.expand_path(lib))
end

require 'rubygems'
gem_paths = [File.expand_path(File.join("gems")),  Gem.default_dir]
Gem.clear_paths
Gem.send :set_paths, gem_paths.join(":")

require 'code/router.rb'

builder = MiniRouter.new

if ENV["RQ_PORT"].nil?
  rq_port = 3333
else
  rq_port = ENV["RQ_PORT"].to_i
end

Rack::Handler::WEBrick.run(builder, :Port => rq_port)
