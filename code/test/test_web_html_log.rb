#!/usr/bin/env ruby

require 'fileutils'
require 'fcntl'
require 'net/http'
require 'uri'

$LOAD_PATH.unshift(File.expand_path("./vendor/gems/json_pure-1.1.6/lib"))
require 'json'

require 'test/unit'
require 'rubygems'
require 'nokogiri'

class TC_HtmlLogsTest < Test::Unit::TestCase
  def setup
    if ENV["RQ_PORT"].nil?
      @rq_port = 3333
    else
      @rq_port = ENV["RQ_PORT"].to_i
    end
  end

  def teardown
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

  def test_html_log
    mesg = { 'dest' => "http://127.0.0.1:#{@rq_port}/q/test",
      'src' => 'test_web_html_log',
      'param1' => 'html'
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
      raise if result['state'] == 'err'
      break if result['state'] == 'done'
    end

    uri_str = "#{msg_id}/log/stdio.log"
    res = Net::HTTP.get_response(URI.parse(uri_str))
    assert_equal("200", res.code)

    doc = Nokogiri::HTML(res.body)

    # Verify that there is a span  elements are hidden

    spans = doc.css("#envspan")
    envspan = spans.pop

    assert_equal("color: blue;", envspan['style'])
  end

end

