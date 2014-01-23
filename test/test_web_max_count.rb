#!/usr/bin/env ruby
$: << File.expand_path('..', File.dirname(__FILE__))

require 'vendor/environment'
require 'fileutils'
require 'fcntl'
require 'net/http'
require 'uri'
require 'json'
require 'test/unit'

class TC_WebAttachErrTest < Test::Unit::TestCase
  def setup
    @rq_port = (ENV['RQ_PORT'] || 3333).to_i
  end

  def run_command(cmd)
    out = `#{cmd}`

    if $?.exitstatus != 0
      return "err", "cmd failed", ""
    end

    results = out.split

    [results[0], results, out]
  end

  def post_new_mesg(mesg)

    form = { :mesg => mesg.to_json }
    remote_q_uri = "http://127.0.0.1:#{@rq_port}/q/test"
    res = Net::HTTP.post_form(URI.parse(remote_q_uri + "/new_message"), form)

    assert_equal("200", res.code)

    result = JSON.parse(res.body)

    assert_equal("ok", result[0])

    msg_id = result[1][/\/q\/[^\/]+\/([^\/]+)/, 1]
    result[1]
  end


  def test_max_count_present_cmdline
    ok,res,_ = run_command("./bin/rq sendmesg  --dest test --src dru4 --relay-ok --param1=resend1 --max_count=3")
    assert_equal("ok", ok)
    msg_id = res[1]

    # Wait for it to change state
    result = {}
    20.times do
      |i|
      sleep 0.2
      uri_str = "#{msg_id}.json"
      res = Net::HTTP.get_response(URI.parse(uri_str))
      assert_equal("200", res.code)
      result = JSON.parse(res.body)
      next if ["prep", "que", "run"].include? result['state']
      break
    end

    assert_equal("done", result['state'])
    assert_equal(1, result['count'])
    assert_equal(3, result['max_count'])
  end

  def test_max_count_present_default_cmdline
    ok,res,_ = run_command("./bin/rq sendmesg  --dest test --src dru4 --relay-ok --param1=resend1")
    assert_equal("ok", ok)
    msg_id = res[1]

    # Wait for it to change state
    result = {}
    20.times do
      |i|
      sleep 0.2
      uri_str = "#{msg_id}.json"
      res = Net::HTTP.get_response(URI.parse(uri_str))
      assert_equal("200", res.code)
      result = JSON.parse(res.body)
      next if ["prep", "que", "run"].include? result['state']
      break
    end

    assert_equal("done", result['state'])
    assert_equal(1, result['count'])
    assert_equal(15, result['max_count'])
  end

  def test_max_count_present_rest_html
    mesg = { 'dest' => "http://127.0.0.1:#{@rq_port}/q/test",
      'src' => 'test',
      'count' => 2,
      'param1' => 'resend1',
      'max_count' => 3,
    }
    msg_id = post_new_mesg(mesg)

    # Wait for it to change state
    result = {}
    20.times do
      |i|
      sleep 0.2
      uri_str = "#{msg_id}.json"
      res = Net::HTTP.get_response(URI.parse(uri_str))
      assert_equal("200", res.code)
      result = JSON.parse(res.body)
      next if ["prep", "que", "run"].include? result['state']
      break
    end

    assert_equal("done", result['state'])

    res = Net::HTTP.get_response(URI.parse(msg_id))
    assert_equal("200", res.code)
    assert_match(/\scount[^:]+:[^2]+2\s/, res.body)
    assert_match(/\smax_count[^:]+:[^3]+3\s/, res.body)
  end

  def test_max_count_present_default_rest_html
    mesg = { 'dest' => "http://127.0.0.1:#{@rq_port}/q/test",
      'src' => 'test',
      'count' => 2,
      'param1' => 'resend1',
    }
    msg_id = post_new_mesg(mesg)

    # Wait for it to change state
    result = {}
    20.times do
      |i|
      sleep 0.2
      uri_str = "#{msg_id}.json"
      res = Net::HTTP.get_response(URI.parse(uri_str))
      assert_equal("200", res.code)
      result = JSON.parse(res.body)
      next if ["prep", "que", "run"].include? result['state']
      break
    end

    assert_equal("done", result['state'])

    res = Net::HTTP.get_response(URI.parse(msg_id))
    assert_equal("200", res.code)
    assert_match(/\scount[^:]+:[^2]+2\s/, res.body)
    assert_match(/\smax_count[^:]+:[^1]+15\s/, res.body)
  end

  def test_max_count_present_rest_json
    mesg = { 'dest' => "http://127.0.0.1:#{@rq_port}/q/test",
      'src' => 'test',
      'count' => 2,
      'param1' => 'resend1',
      'max_count' => 3,
    }
    msg_id = post_new_mesg(mesg)

    # Wait for it to change state
    result = {}
    20.times do
      |i|
      sleep 0.2
      uri_str = "#{msg_id}.json"
      res = Net::HTTP.get_response(URI.parse(uri_str))
      assert_equal("200", res.code)
      result = JSON.parse(res.body)
      next if ["prep", "que", "run"].include? result['state']
      break
    end

    assert_equal("done", result['state'])
    assert_equal(2, result['count'])
    assert_equal(3, result['max_count'])
  end


  def test_max_count_limit_rest_resend
    # this script just resends to itself in the queue
    mesg = { 'dest' => "http://127.0.0.1:#{@rq_port}/q/test",
      'src' => 'test',
      'count' => 2,
      'param1' => 'resend2',
      'max_count' => 3,
    }
    msg_id = post_new_mesg(mesg)

    # Wait for it to change state
    result = {}
    20.times do
      |i|
      sleep 0.2
      uri_str = "#{msg_id}.json"
      res = Net::HTTP.get_response(URI.parse(uri_str))
      assert_equal("200", res.code)
      result = JSON.parse(res.body)
      next if ["prep", "que", "run"].include? result['state']
      break
    end

    assert_equal("err", result['state'])
    assert_equal(3, result['count'])
    assert_equal(3, result['max_count'])
  end

  def test_max_count_not_hit_rest_resend
    # this script just resends to itself in the queue
    mesg = { 'dest' => "http://127.0.0.1:#{@rq_port}/q/test",
      'src' => 'test',
      'param1' => 'resend2',
      'max_count' => 8,
    }
    msg_id = post_new_mesg(mesg)

    # Wait for it to change state
    result = {}
    20.times do
      |i|
      sleep 0.2
      uri_str = "#{msg_id}.json"
      res = Net::HTTP.get_response(URI.parse(uri_str))
      assert_equal("200", res.code)
      result = JSON.parse(res.body)
      next if ["prep", "que", "run"].include? result['state']
      break
    end

    assert_equal("done", result['state'])
    assert_equal(6, result['count'])
    assert_equal(8, result['max_count'])
  end


end

