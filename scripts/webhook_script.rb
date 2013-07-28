#!/usr/bin/env ruby

require 'net/http'
require 'uri'

# Setup a global binding so the GC doesn't close the file
$RQ_IO = IO.for_fd(ENV['RQ_WRITE'].to_i)

# IO tower to RQ mgr process
def write_status(state, mesg = '')
  msg = "#{state} #{mesg}\n"

  STDOUT.write("#{Process.pid} - #{Time.now} - #{msg}")
  $RQ_IO.syswrite(msg)
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
  exit(0)
end

def send_post
  # Construct form post message
  mesg = {}
  mesg['x_format'] = 'json'
  mesg['payload'] = ENV['RQ_PARAM2']

  uri = ENV['RQ_PARAM1']

  write_status('run', "Attempting post to url: #{uri}")

  begin
    res = Net::HTTP.post_form(URI.parse(uri), mesg)
  rescue
    handle_fail("Could not connect to or parse URL: #{uri}")
  end

  if res.code.to_s =~ /2\d\d/
    write_status('done', "successfull post #{res.code.to_s}")
  else
    handle_fail("Could not POST to URL: #{res.inspect}")
  end
end

send_post()
