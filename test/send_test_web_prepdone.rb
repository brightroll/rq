#!/usr/bin/env ruby
$: << File.expand_path('..', File.dirname(__FILE__))

require 'vendor/environment'
require 'net/http'
require 'uri'
require 'fileutils'
require 'fcntl'
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


# commit message

form = { :x_format => 'json', '_method' => 'commit', :msg_id => msg_id }

# Get the URL
res = Net::HTTP.post_form(URI.parse(remote_q_uri + "/#{msg_id}"), form)

if res.code != '200'
  print "Sorry, system couldn't commit test message properly\n"
  exit 1
end

result = JSON.parse(res.body)

if result[0] != 'ok'
  print "Sorry, system couldn't commit test message properly : #{res.body}\n"
  exit 1
end

print "Committed message: #{msg_id}\n"


# verify done message

4.times do

  ## Verify that script goes to done state

  remote_q_uri = "http://127.0.0.1:#{rq_port}/q/test/#{msg_id}.json"
  res = Net::HTTP.get_response(URI.parse(remote_q_uri))

  if res.code == '200'
    msg = JSON.parse(res.body)
    if msg['status'] == 'done - done sleeping'
        print "Message went into proper state. ALL DONE\n"
        exit 0
    end
  end

  #print "-=-=-=-\n"
  #print res.code
  #print res.body
  #print "\n"
  #print "-=-=-=-\n"

  sleep 1
end



print "FAIL - system didn't get a message in proper state: #{res.body}\n"
exit 1
    
