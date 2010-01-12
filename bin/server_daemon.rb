#!/usr/bin/ruby

$:.unshift(File.join(File.dirname(__FILE__), ".."))

Dir.glob(File.join("gems", "gems", "*", "lib")).each do |lib|
  $LOAD_PATH.unshift(File.expand_path(lib))
end

Dir.chdir(File.join(File.dirname(__FILE__), ".."))

require 'rubygems'
gem_paths = [File.expand_path(File.join("gems")),  Gem.default_dir]
Gem.clear_paths
Gem.send :set_paths, gem_paths.join(":")

require 'code/router.rb'

builder = MiniRouter.new

pid = fork do
  Signal.trap('HUP', 'IGNORE') # Don't die upon logout
  
  FileUtils.mkdir_p("log")

  STDIN.reopen("/dev/null")
  STDOUT.reopen("log/server.log", "w")
  $stderr = STDOUT

  Rack::Handler::WEBrick.run(builder, :Port => 3333)
end

Process.detach(pid)

