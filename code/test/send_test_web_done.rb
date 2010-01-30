#!/usr/bin/env ruby


require 'gems/environment'

require 'net/http'
require 'uri'
require 'fileutils'
require 'fcntl'

def log(mesg)
  print "#{Process.pid} - #{Time.now} - #{mesg}\n"
end


#Dir.glob(File.join( "code", "vendor", "gems", "*", "lib")).each do |lib|
#  $LOAD_PATH.unshift(File.expand_path(lib))
#end
#Dir.glob(File.join("..", "..", "..", "..", "..")).each do |lib|
#  $LOAD_PATH.unshift(File.expand_path(lib))
#end


require 'rubygems'
#gem_paths = [File.expand_path(File.join("code", "vendor", "gems")),  Gem.default_dir]
#Gem.clear_paths
#Gem.send :set_paths, gem_paths.join(":")

#log($LOAD_PATH.inspect)
#log(Dir.pwd.inspect)
#log(gem_paths.inspect)

require 'json'


## TEST SECTION

if ENV["RQ_PORT"].nil?
  rq_port = 3333
else
  rq_port = ENV["RQ_PORT"].to_s
end


mesg = { 'dest' => "http://localhost:#{rq_port}/q/test",
         'src'  => 'test',
         'count'  => '2',
         'param1'  => 'done',
       }

form = { :x_format => 'json', :mesg => mesg.to_json }

# Get the URL
remote_q_uri = "http://localhost:#{rq_port}/q/test"
res = Net::HTTP.post_form(URI.parse(remote_q_uri + "/new_message"), form)


if res.code != '200'
  print "Sorry, system didn't create test message properly\n"
  exit 1
end

result = JSON.parse(res.body)

if result[0] != 'ok'
  print "Sorry, system didn't create test message properly : #{res.body}\n"
  exit 1
end

print "Committed message: #{result[1]}\n"

msg_id = result[1][/\/q\/[^\/]+\/([^\/]+)/, 1]

print "Msg ID: #{msg_id}\n"

4.times do

  ## Verify that script goes to done state

  remote_q_uri = "http://localhost:#{rq_port}/q/test/#{msg_id}.json"
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
    
