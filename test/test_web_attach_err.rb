#!/usr/bin/env ruby
$: << File.expand_path('..', File.dirname(__FILE__))

require 'vendor/environment'
require 'fileutils'
require 'fcntl'
require 'net/http'
require 'uri'

require 'test/unit'

class TC_WebAttachErrTest < Test::Unit::TestCase
  # def setup
  # end

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

  def test_num_entries
    # Create attachement
    ok,res,_ = run_command("./bin/rq prepmesg  --dest test --src dru4 --relay-ok --param1=err")
    assert_equal("ok", ok)
    msg_id = res[1]

    ok,res,out = run_command("./bin/rq attachmesg  --msg_id #{msg_id} --pathname test/fixtures/studio3.jpg")
    assert_equal("ok", ok)
    expected="ok 14a1a7845cc7f981977fbba6a60f0e42-Attached successfully for Message: #{msg_id} attachment\n"
    assert_equal(expected, out)

    ok,_,_ = run_command("./bin/rq commitmesg  --msg_id #{msg_id}")
    assert_equal("ok", ok)

    # Wait for it to change state
    20.times do
      |i|
      ok,res,_ = run_command("./bin/rq statusmesg  --msg_id #{msg_id}")
      sleep 0.1
      next if ["prep", "que", "run"].include? res[1]
      assert_equal("err", res[1])
      break
    end

    # Check that you can read attachment from err
    uri_str = "#{msg_id}/attach/studio3.jpg"
    res = Net::HTTP.get_response(URI.parse(uri_str))
    assert_equal("200", res.code)
  end

end

