#!/usr/bin/env ruby
$: << File.expand_path('..', File.dirname(__FILE__))

require 'vendor/environment'
require 'fileutils'
require 'fcntl'
require 'net/http'
require 'uri'
require 'json'
require 'code/queueclient'
require 'test/unit'

class TC_ConfigChangeTest < Test::Unit::TestCase
  def setup
    @rq_port = (ENV['RQ_PORT'] || 3333).to_i
  end

  # def teardown
  # end

  def test_config_change

    # Create the queue if needed

    ## Get queue list
    uri_str = "http://127.0.0.1:#{@rq_port}/q.json"
    res = Net::HTTP.get_response(URI.parse(uri_str))
    assert_equal("200", res.code)

    queue_names = JSON.parse(res.body)

    has_queue = queue_names.include? 'test_change'

    ## Delete queue if it exists
    if has_queue
      uri_str = "http://127.0.0.1:#{@rq_port}/delete_queue"
      res = Net::HTTP.post_form(URI.parse(uri_str),
                                { 'queue_name' => 'test_change' })
      assert_equal("303", res.code)
    end

    # Poll to make sure queue is deleted
    while has_queue
      uri_str = "http://127.0.0.1:#{@rq_port}/q.json"
      res = Net::HTTP.get_response(URI.parse(uri_str))
      assert_equal("200", res.code)

      queue_names = JSON.parse(res.body)

      has_queue = queue_names.include? 'test_change'
    end

    ## Create the queue
    uri_str = "http://127.0.0.1:#{@rq_port}/new_queue_link"
    res = Net::HTTP.post_form(URI.parse(uri_str),
                              { 'queue[json_path]' => './test/fixtures/jsonconfigfile/good.json'})
    assert_equal("303", res.code)


    # Get queue's config
    uri_str = "http://127.0.0.1:#{@rq_port}/q/test_change/config"
    res = Net::HTTP.get_response(URI.parse(uri_str))
    assert_equal("200", res.code)

    result = JSON.parse(res.body)
    assert_equal(1, result['num_workers'])

    new_config_path = './test/fixtures/jsonconfigfile/good_new.json'
    config_path = 'queue/test_change/config.json'

    # Change the config
    FileUtils.cp(new_config_path, config_path + '.tmp')
    FileUtils.mv(config_path + '.tmp', config_path)

    # Send a HUP
    pid_str = File.read('queue/test_change/queue.pid')
    Process.kill("HUP", pid_str.to_i)

    sleep(0.010) # sleep 10 ms

    # Get queue's config
    uri_str = "http://127.0.0.1:#{@rq_port}/q/test_change/config"
    res = Net::HTTP.get_response(URI.parse(uri_str))
    assert_equal("200", res.code)

    result = JSON.parse(res.body)
    assert_equal(4, result['num_workers'])
  end

end
