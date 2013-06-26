#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'fileutils'
require 'fcntl'

def log(mesg)
  print "#{Process.pid} - #{Time.now} - #{mesg}\n"
end

log(Dir.pwd.inspect)

$LOAD_PATH.unshift(File.expand_path("./vendor/gems/json_pure-1.1.6/lib"))
require 'json'

## TEST SECTION

# prep message

rq_port = (ENV['RQ_PORT'] || 3333).to_i


mesg = { 'dest' => "http://127.0.0.1:#{rq_port}/q/test",
         'src'  => 'test',
         'count'  => '2',
         'param1'  => 'done',
         '_method'  => 'prep',
       }

form = { :mesg => mesg.to_json }

# Get the URL
remote_q_uri = "http://127.0.0.1:#{rq_port}/q/test"
res = Net::HTTP.post_form(URI.parse(remote_q_uri + "/new_message"), form)

if res.code != '200'
  print "Sorry, system didn't create test message properly\n"
  print "#{res.inspect}\n"
  exit 1
end

result = JSON.parse(res.body)

if result[0] != 'ok'
  print "Sorry, system didn't create test message properly : #{res.body}\n"
  exit 1
end

print "Prepped message: #{result[1]}\n"

msg_id = result[1][/\/q\/[^\/]+\/([^\/]+)/, 1]

print "Msg ID: #{msg_id}\n"


# attach message


pipe_res = `./test/mime_test.rb #{msg_id}`

#p $?
#p pipe_res
# Get the URL
#res = Net::HTTP.post_form(URI.parse(remote_q_uri + "/#{msg_id}/attach/new"), form)

if $?.exitstatus != 0
  print "Sorry, system couldn't attach to test message properly\n"
  print "Exit status: #{$?.exitstatus.inspect}\n"
  print pipe_res
  exit 1
end


print "Message went into proper state. ALL DONE\n"
