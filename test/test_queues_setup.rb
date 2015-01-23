#!/usr/bin/env ruby
$: << File.expand_path('..', File.dirname(__FILE__))

require 'vendor/environment'
require 'net/http'
require 'uri'
require 'fileutils'
require 'fcntl'
require 'json'

def log(mesg)
  print "#{Process.pid} - #{Time.now} - #{mesg}\n"
end

log(Dir.pwd.inspect)

## TEST SECTION

rq_port = (ENV['RQ_PORT'] || 3333).to_i

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
#{"script":"./test/test_script.sh","name":"test","url":"http://127.0.0.1:3333/","num_workers":"1"}
#
test_key 'test', result, 'name', 'test'
test_key 'test', result, 'num_workers', 1
test_key 'test', result, 'script', './test/test_script.sh'
test_key 'test', result, 'coalesce_params', []
test_key 'test', result, 'blocking_params', []
test_key 'test', result, 'exec_prefix', ''



uri_str = "http://127.0.0.1:#{rq_port}/q/test_coalesce/config.json"
res = Net::HTTP.get_response(URI.parse(uri_str))

if res.code != '200'
  print "Sorry, system didn't create the test_coalesce que properly\n"
  print "#{res.inspect}\n"
  exit 1
end

result = JSON.parse(res.body)

test_key 'test_coalesce', result, 'name', 'test_coalesce'
test_key 'test_coalesce', result, 'num_workers', 1
test_key 'test_coalesce', result, 'script', './test/test_script.sh'
test_key 'test_coalesce', result, 'exec_prefix', ''
test_key 'test_coalesce', result, 'coalesce_params', [1]
test_key 'test_coalesce', result, 'blocking_params', []
