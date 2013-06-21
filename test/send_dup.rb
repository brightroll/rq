#!/usr/bin/env ruby

require 'fileutils'
require 'fcntl'
require 'net/http'
require 'uri'

$LOAD_PATH.unshift(File.expand_path("./vendor/gems/json_pure-1.1.6/lib"))
require 'json'

require 'test/unit'

class TC_SendDupTest < Test::Unit::TestCase

  def setup
    @rq_port = (ENV['RQ_PORT'] || 3333).to_i
  end

  # def teardown
  # end

  def run_command(cmd)
    out = `#{cmd}`

    if $?.exitstatus != 0
      return "err", "cmd failed", ""
    end

    results = out.split

    [results[0], results, out]
  end

  def test_dup_direct_ok_msg
    ok,res,_ = run_command("./bin/rq sendmesg  --dest test --src dru4 --relay-ok --param1=dup_direct --param2=/tmp/rq_test_dup_test_rb1")
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

    new_msg_id = File.read("/tmp/rq_test_dup_test_rb1").strip
    File.unlink("/tmp/rq_test_dup_test_rb1")

    # Wait for it to change state
    result = {}
    20.times do
      |i|
      sleep 0.2
      uri_str = "#{new_msg_id}.json"
      res = Net::HTTP.get_response(URI.parse(uri_str))
      assert_equal("200", res.code)
      result = JSON.parse(res.body)
      next if ["prep", "que", "run"].include? result['state']
      break
    end

    assert_equal("done", result['state'])
    assert_equal("dup_direct", result['param1'])
    assert_equal("dru4", result['src'])
  end

  def test_dup_relay_ok_msg
    ok,res,_ = run_command("./bin/rq sendmesg  --dest test --src dru4 --relay-ok --param1=dup_relay --param2=/tmp/rq_test_dup_test_rb3")
    assert_equal("ok", ok)
    msg_id = res[1]

    # Wait for it to change state (relayed)
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

    new_msg_id = File.read("/tmp/rq_test_dup_test_rb3").strip
    File.unlink("/tmp/rq_test_dup_test_rb3")

    # Wait for it to change state
    result = {}
    20.times do
      |i|
      sleep 0.2
      uri_str = "#{new_msg_id}.json"
      res = Net::HTTP.get_response(URI.parse(uri_str))
      assert_equal("200", res.code)
      result = JSON.parse(res.body)
      next if ["prep", "que", "run"].include? result['state']
      break
    end

    assert_equal("relayed", result['state'])
    assert_equal("dup_relay", result['param1'])
    assert_equal("dru4", result['src'])

    next_msg_id = result['status'].split(' - ', 2)[1]

    # Wait for it to go to done
    result = {}
    20.times do
      |i|
      sleep 0.2
      uri_str = "#{next_msg_id}.json"
      res = Net::HTTP.get_response(URI.parse(uri_str))
      assert_equal("200", res.code)
      result = JSON.parse(res.body)
      next if ["prep", "que", "run"].include? result['state']
      break
    end

    assert_equal("done", result['state'])
    assert_equal("dup_relay", result['param1'])
    assert_equal("dru4", result['src'])
  end

  def test_dup_direct_attach_ok_msg
    ok,res,_ = run_command("./bin/rq prepmesg  --dest test --src dru4 --relay-ok --param1=dup_direct --param2=/tmp/rq_test_dup_test_rb5")
    assert_equal("ok", ok)
    msg_id = res[1]

    ok,res,out = run_command("./bin/rq attachmesg  --msg_id #{msg_id} --pathname code/test/fixtures/studio3.jpg")
    assert_equal("ok", ok)
    expected="ok 14a1a7845cc7f981977fbba6a60f0e42-Attached successfully for Message: #{msg_id} attachment\n"
    assert_equal(expected, out)

    ok,_,_ = run_command("./bin/rq commitmesg  --msg_id #{msg_id}")
    assert_equal("ok", ok)

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

    new_msg_id = File.read("/tmp/rq_test_dup_test_rb5").strip
    File.unlink("/tmp/rq_test_dup_test_rb5")

    # Wait for it to change state
    result = {}
    20.times do
      |i|
      sleep 0.2
      uri_str = "#{new_msg_id}.json"
      res = Net::HTTP.get_response(URI.parse(uri_str))
      assert_equal("200", res.code)
      result = JSON.parse(res.body)
      next if ["prep", "que", "run"].include? result['state']
      break
    end

    assert_equal("done", result['state'])
    assert_equal("dup_direct", result['param1'])
    assert_equal("dru4", result['src'])

    # Check that you can read attachment from dup'd message
    uri_str = "#{new_msg_id}/attach/studio3.jpg"
    res = Net::HTTP.get_response(URI.parse(uri_str))
    assert_equal("200", res.code)
  end

  def test_dup_relay_attach_ok_msg
    ok,res,_ = run_command("./bin/rq prepmesg  --dest test --src dru4 --relay-ok --param1=dup_relay --param2=/tmp/rq_test_dup_test_rb6")
    assert_equal("ok", ok)
    msg_id = res[1]

    ok,res,out = run_command("./bin/rq attachmesg  --msg_id #{msg_id} --pathname code/test/fixtures/studio3.jpg")
    assert_equal("ok", ok)
    expected="ok 14a1a7845cc7f981977fbba6a60f0e42-Attached successfully for Message: #{msg_id} attachment\n"
    assert_equal(expected, out)

    ok,_,_ = run_command("./bin/rq commitmesg  --msg_id #{msg_id}")
    assert_equal("ok", ok)

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

    new_msg_id = File.read("/tmp/rq_test_dup_test_rb6").strip
    File.unlink("/tmp/rq_test_dup_test_rb6")

    # Wait for it to change state (relay)
    result = {}
    20.times do
      |i|
      sleep 0.2
      uri_str = "#{new_msg_id}.json"
      res = Net::HTTP.get_response(URI.parse(uri_str))
      assert_equal("200", res.code)
      result = JSON.parse(res.body)
      next if ["prep", "que", "run"].include? result['state']
      break
    end

    assert_equal("relayed", result['state'])
    assert_equal("dup_relay", result['param1'])
    assert_equal("dru4", result['src'])

    next_msg_id = result['status'].split(' - ', 2)[1]

    # Wait for it to go to done
    result = {}
    20.times do
      |i|
      sleep 0.2
      uri_str = "#{next_msg_id}.json"
      res = Net::HTTP.get_response(URI.parse(uri_str))
      assert_equal("200", res.code)
      result = JSON.parse(res.body)
      next if ["prep", "que", "run"].include? result['state']
      break
    end

    assert_equal("done", result['state'])
    assert_equal("dup_relay", result['param1'])
    assert_equal("dru4", result['src'])

    # Check that you can read attachment from dup'd message
    uri_str = "#{new_msg_id}/attach/studio3.jpg"
    res = Net::HTTP.get_response(URI.parse(uri_str))
    assert_equal("200", res.code)
  end

  def test_dup_fail_msg
    ok,res,_ = run_command("./bin/rq sendmesg  --dest test --src dru4 --relay-ok --param1=dup_fail --param2=/tmp/rq_test_dup_test_rb2")
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

    response = File.read("/tmp/rq_test_dup_test_rb2").strip
    File.unlink("/tmp/rq_test_dup_test_rb2")

    assert_equal("fail couldn't connect to queue - nope_this_q_does_not_exist", response)
  end

end

