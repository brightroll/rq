#!/usr/bin/env ruby
$: << File.expand_path('..', File.dirname(__FILE__))

require 'vendor/environment'
require 'test/unit'
require 'net/http'
require 'uri'
require 'json'

class TC_EnvVarTest < Test::Unit::TestCase

  def run_command(cmd)
    out = `#{cmd}`

    if $?.exitstatus != 0
      return "err", "cmd failed", ""
    end

    results = out.split

    [results[0], results, out]
  end

  def test_queue_message
    ok,res,_ = run_command("./bin/rq sendmesg --dest test_env_var --src unittest --relay-ok")
    assert_equal("ok", ok)
    msg_id = res[1]

    # Wait for it to change state
    result = {}
    20.times do |i|
      sleep 0.2
      uri_str = "#{msg_id}.json"
      res = Net::HTTP.get_response(URI.parse(uri_str))
      assert_equal("200", res.code)
      result = JSON.parse(res.body)
      next if ["prep", "que", "run"].include? result['state']
      break
    end

    assert_equal("done", result['state'])
  end

end
