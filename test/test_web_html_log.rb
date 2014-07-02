#!/usr/bin/env ruby
$: << File.expand_path('..', File.dirname(__FILE__))

require 'vendor/environment'
require 'fileutils'
require 'fcntl'
require 'net/http'
require 'uri'
require 'test/unit'

require 'json'

require 'rubygems' if RUBY_VERSION < '1.9'
require 'nokogiri'

class TC_HtmlLogsTest < Test::Unit::TestCase
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
    remote_q_uri = mesg['dest']
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


    assert_match(/&lt;HTML UNSAFE 'CHARS' TEST &amp; OTHER FRIENDS&gt;/m, res.body, message="Missing nicely escaped string")

    doc = Nokogiri::HTML(res.body)

    # Verify that there is a span  elements are hidden

    links = []
    anchors = doc.css("a")
    anchors.each do |link|
      links << link.content
    end

    # Filter links that aren't RQ
    links.delete_if { |link|
      !link.match(/#{@rq_port}/)
    }

    assert_equal(10, links.length)
  end

  def test_ansi_log
    mesg = { 'dest' => "http://127.0.0.1:#{@rq_port}/q/test_ansi",
      'src' => 'test_web_html_log/test_ansi_log',
      'param1' => ''
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

    anchors = doc.css("a")

    assert_equal("http://xxeo.com/", anchors[0]['href'])
    assert_equal("http://www.brightroll.com/", anchors[1]['href'])


    assert_match(/&amp; &amp;&lt; &lt; &gt;/m, res.body, message="Missing nicely escaped string")

    spans = doc.css("span")

    assert_equal(6 * 8 * 8, spans.length)
  end

end

