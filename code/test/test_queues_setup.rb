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

if ENV["RQ_PORT"].nil?
  rq_port = 3333
else
  rq_port = ENV["RQ_PORT"].to_s
end


uri_str = "http://127.0.0.1:#{rq_port}/q/test/config.json"
res = Net::HTTP.get_response(URI.parse(uri_str))

if res.code != '200'
  print "Sorry, system didn't create the test que properly\n"
  print "#{res.inspect}\n"
  exit 1
end

result = JSON.parse(res.body)

def test_key(que_name, under_test, key, expected)
  if under_test[key] != expected
    print "Sorry, system didn't configure '#{que_name}' que properly: incorrect '#{key}' value: '#{under_test[key]}'\n"
    exit 1
  end
end

# expected
#{"script":".\/code\/test\/test_script.sh","name":"test","url":"http:\/\/127.0.0.1:3333\/","num_workers":"1"}
#
test_key 'test', result, 'name', 'test'
test_key 'test', result, 'num_workers', '1'
test_key 'test', result, 'script', './code/test/test_script.sh'
test_key 'test', result, 'url', "http://127.0.0.1:#{rq_port}/"
test_key 'test', result, 'coalesce', 'no'



uri_str = "http://127.0.0.1:#{rq_port}/q/test_coalesce/config.json"
res = Net::HTTP.get_response(URI.parse(uri_str))

if res.code != '200'
  print "Sorry, system didn't create the test_coalesce que properly\n"
  print "#{res.inspect}\n"
  exit 1
end

result = JSON.parse(res.body)

test_key 'test_coalesce', result, 'name', 'test_coalesce'
test_key 'test_coalesce', result, 'num_workers', '1'
test_key 'test_coalesce', result, 'script', './code/test/test_script.sh'
test_key 'test_coalesce', result, 'url', "http://127.0.0.1:#{rq_port}/"
test_key 'test_coalesce', result, 'coalesce', 'yes'
test_key 'test_coalesce', result, 'coalesce_param1', '1'
test_key 'test_coalesce', result, 'coalesce_param2', nil
test_key 'test_coalesce', result, 'coalesce_param3', nil
test_key 'test_coalesce', result, 'coalesce_param4', nil


