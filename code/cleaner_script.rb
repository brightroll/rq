#!/usr/bin/env ruby

require 'fileutils'
require 'fcntl'


def log(mesg)
  m = "#{Process.pid} - #{Time.now} - #{mesg}\n"
  File.open('relay.log', "a") do
    |f|
    f.write(m)
  end
  print m
end


Dir.glob(File.join("..", "..", "..", "..", "..", "code", "vendor", "gems", "*", "lib")).each do |lib|
  $LOAD_PATH.unshift(File.expand_path(lib))
end
Dir.glob(File.join("..", "..", "..", "..", "..")).each do |lib|
  $LOAD_PATH.unshift(File.expand_path(lib))
end


require 'rubygems'
gem_paths = [File.expand_path(File.join("..", "..", "..", "..", "..", "code", "vendor", "gems")),  Gem.default_dir]
Gem.clear_paths
Gem.send :set_paths, gem_paths.join(":")

#log($LOAD_PATH.inspect)
log(Dir.pwd.inspect)
#log(gem_paths.inspect)

require 'json'

# Setup a global binding so the GC doesn't close the file
$RQ_IO = IO.for_fd(ENV['RQ_PIPE'].to_i)

# Had to use \n
# I tried to use \000 but bash barfed on me
def write_status(state, mesg = '')
  msg = "#{state} #{mesg}\n"
  $RQ_IO.syswrite(msg)
  log("#{state} #{mesg}")
end

def soft_fail(mesg = 'soft fail')
  count = ENV['RQ_COUNT'].to_i
  wait_seconds = count * count * 10
  write_status('resend', "#{wait_seconds}-#{mesg}")
  log("RESEND - #{wait_seconds} - #{count} - #{mesg}")
  exit(0)
end




write_status('done', 'to be implemented')


