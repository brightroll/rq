#!/usr/bin/env ruby
$: << File.expand_path('..', File.dirname(__FILE__))

require 'vendor/environment'
require 'net/http'
require 'uri'
require 'fileutils'
require 'fcntl'
require 'json'
require 'test/unit'

class TC_WebSearch < Test::Unit::TestCase
  def setup
    @rq_port = (ENV['RQ_PORT'] || 3333).to_i
    @base_uri = "http://127.0.0.1:#{@rq_port}/search?name=test_search"
    @param1 = "http://127.0.0.1:#{@rq_port}/search?name=test_search&query[param1]=ear"
    @empty = "http://127.0.0.1:#{@rq_port}/search?name=test_search&query[fakestuff]=asdfasdf"

    @messages = [
        { 'dest' => "http://127.0.0.1:#{@rq_port}/q/test_search",
          'src' => 'test_search',
          'param1' => 'ear',
          '_method' => 'prep'
        },
        { 'dest' => "http://127.0.0.1:#{@rq_port}/q/test_search",
          'src' => 'test_search',
          'param1' => 'hello:pear',
          '_method' => 'prep'
        },
        { 'dest' => "http://127.0.0.1:#{@rq_port}/q/test_search",
          'src' => 'test_search',
          'param1' => 'search',
          '_method' => 'prep'
        },
        { 'dest' => "http://127.0.0.1:#{@rq_port}/q/test_search",
          'src' => 'test_search',
          'param1' => 'html',
          '_method' => 'prep'
        },
        { 'dest' => "http://127.0.0.1:#{@rq_port}/q/test_search",
          'src' => 'test_search',
          'param1' => 'html',
          '_method' => 'prep'
        }
    ]
    @message_ids = @messages.map do |m|
      post_new_mesg(m)
    end
  end

  def teardown
    @message_ids.each do |m|
      Net::HTTP.post_form(URI.parse(m), { '_method' => 'delete' })
    end
  end

  def post_new_mesg(mesg)
    uri = URI.parse(mesg['dest'] + '/new_message')
    http = Net::HTTP.new(uri.host, uri.port)
    res = http.post(uri.path, mesg.to_json, {'Content-Type' => 'application/json'})

    assert_equal('200', res.code)
    result = JSON.parse(res.body)
    assert_equal('ok', result[0])

    result[1]
  end

  def test_search_all_urls
    res = Net::HTTP.get_response(URI.parse(@base_uri))

    assert_equal("200", res.code)
    assert_equal(@messages.length, JSON.parse(res.body).length)

    res = Net::HTTP.get_response(URI.parse(@param1))

    assert_equal("200", res.code)
    assert_equal(3, JSON.parse(res.body).length)

    res = Net::HTTP.get_response(URI.parse(@param1+"&exact=true"))

    assert_equal("200", res.code)
    assert_equal(1, JSON.parse(res.body).length)


    res = Net::HTTP.get_response(URI.parse(@empty))

    assert_equal("200", res.code)
    assert_equal(0, JSON.parse(res.body).length)
  end
end
