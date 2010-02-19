#!/usr/bin/env ruby

require 'net/http'
require 'uri'

##############################
# would love to get rid of all this garbage

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

# would love to get rid of all this garbage
##############################

def log(mesg)
  STDOUT.write("#{Process.pid} - #{Time.now} - #{mesg}\n")
end

# Setup a global binding so the GC doesn't close the file
$RQ_IO = IO.for_fd(ENV['RQ_PIPE'].to_i)

# Had to use \n
# I tried to use \000 but bash barfed on me
def write_status(state, mesg = '')
  msg = "#{state} #{mesg}\n"
  $RQ_IO.syswrite(msg)
  log("#{state} #{mesg}")
end

def handle_fail(mesg = 'soft fail')
  count = ENV['RQ_COUNT'].to_i

  if count > 15
    write_status('run', "RQ_COUNT > 15 - failing")
    write_status('fail', "RQ_COUNT > 15 - failing")
    exit(0)
  end

  wait_seconds = count * count * 60
  write_status('resend', "#{wait_seconds}-#{mesg}")
  log("RESEND - #{wait_seconds} - #{count} - #{mesg}")
  exit(0)
end

def send_post
  # Construct form post message
  mesg = {}
  mesg['x_format'] = 'json'
  mesg['payload'] = ENV['RQ_PARAM2']

  write_status('run', "Attempting post to url: #{ENV['RQ_PARAM1']}")

  res = Net::HTTP.post_form(URI.parse(ENV['RQ_PARAM1']), mesg)

  if res.code.to_s =~ /2\d\d/
    write_status('done', "successfull post #{res.code.to_s}")
  else
    handle_fail("Could not POST to URL: #{res.inspect}")
  end
end

send_post()
