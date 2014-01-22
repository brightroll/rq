#!/usr/bin/env ruby
$: << File.expand_path('..', File.dirname(__FILE__))

require 'vendor/environment'
require 'net/http'
require 'uri'
require 'fileutils'
require 'fcntl'
require 'json'

## TEST SECTION

rq_port = (ENV['RQ_PORT'] || 3333).to_i

def test_result(obj, idx)
  if obj[idx] !~ /^\d\d\d\d\d\d\d\d.\d\d\d\d.\d\d.\d\d\d.\d+$/
    puts "JSON response not right: result[#{idx}] wasn't a message id: '#{obj[idx].inspect}'"
    exit 1
  end
end

uri_str = "http://127.0.0.1:#{rq_port}/q/test/done.json?limit=2"
res = Net::HTTP.get_response(URI.parse(uri_str))

if res.code != '200'
  print "Sorry, system didn't create the test que properly\n"
  print "#{res.inspect}\n"
  exit 1
end

result = JSON.parse(res.body)

if result.length != 2
  print "JSON response not length 2 -> '#{result.inspect}' que properly: incorrect '#{key}' value: '#{under_test[key]}'\n"
  exit 1
end

if result != (result.sort.reverse) 
  puts "JSON response not right: wasn't in reverse sort order: '#{result.inspect}'"
  exit 1
end

test_result(result, 0)
test_result(result, 1)

uri_str = "http://127.0.0.1:#{rq_port}/q/test/done.json"
res = Net::HTTP.get_response(URI.parse(uri_str))

if res.code != '200'
  print "Sorry, system didn't create the test que properly\n"
  print "#{res.inspect}\n"
  exit 1
end

result = JSON.parse(res.body)

if result.length != 10
  print "JSON response not length 2 -> '#{result.inspect}' que properly: incorrect '#{key}' value: '#{under_test[key]}'\n"
  exit 1
end

if result != (result.sort.reverse) 
  puts "JSON response not right: wasn't in reverse sort order: '#{result.inspect}'"
  exit 1
end

test_result(result, 0)
test_result(result, 1)
test_result(result, 2)
test_result(result, 3)
test_result(result, 4)
test_result(result, 5)
test_result(result, 6)
test_result(result, 7)
test_result(result, 8)
test_result(result, 9)

puts "PASSED"
