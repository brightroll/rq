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
    @messages.each do |m|
      post_new_mesg(m)
    end
  end

  def post_new_mesg(mesg)
    form = { :mesg => mesg.to_json }
    remote_q_uri = mesg['dest']
      res = Net::HTTP.post_form(URI.parse(remote_q_uri + "/new_message"), form)
    assert_equal("200", res.code)

    result = JSON.parse(res.body)

    assert_equal("ok", result[0])

    msg_id = result[1][/\/q\/[^\/]+\/([^\/]+)/, 1]
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