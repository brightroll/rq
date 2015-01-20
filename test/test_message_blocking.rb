#!/usr/bin/env ruby
$: << File.expand_path('..', File.dirname(__FILE__))

require 'vendor/environment'
require 'test/unit'
require 'fileutils'
require 'code/queue'
require 'code/queueclient'
require 'logger'

class TC_MessageBlockingTest < Test::Unit::TestCase

  def setup
    FileUtils.rm(Dir.glob('test/tmp/unlock*'), :force => true)
    $log = Logger.new(STDOUT)
    @qc = RQ::QueueClient.new("test_blocking")
  end

  def teardown
    FileUtils.rm(Dir.glob('test/tmp/unlock*'), :force => true)
  end

  def test_running
    assert_equal(1, @qc.running?, "Running")
  end

  def test_blocking
    mesg1 = {}
    mesg1["dest"] = "test_blocking"
    mesg1["param1"] = "a"
    mesg1["param2"] = "unlock1"

    mesg2 = {}
    mesg2["dest"] = "test_blocking"
    mesg2["param1"] = "b"
    mesg2["param2"] = "unlock2"

    mesg3 = {}
    mesg3["dest"] = "test_blocking"
    mesg3["param1"] = "a"
    mesg3["param2"] = "unlock3"

    ok1, job1 = @qc.create_message(mesg1)
    ok2, job2 = @qc.create_message(mesg2)
    ok3, job3 = @qc.create_message(mesg3)

    assert_equal("ok", ok1, "Create msg1")
    assert_equal("ok", ok2, "Create msg2")
    assert_equal("ok", ok3, "Create msg3")

    ok1, state1 = @qc.get_message_state({:msg_id => strip_queue_prefix(job1)})
    ok2, state2 = @qc.get_message_state({:msg_id => strip_queue_prefix(job2)})
    ok3, state3 = @qc.get_message_state({:msg_id => strip_queue_prefix(job3)})

    assert_equal("run", state1, "Msg1 running")
    assert_equal("run", state2, "Msg2 running")
    assert_equal("que", state3, "Msg3 blocked in que")

    FileUtils.touch("test/tmp/unlock1")
    FileUtils.touch("test/tmp/unlock2")

    sleep(1.0)

    ok1, state1 = @qc.get_message_state({:msg_id => strip_queue_prefix(job1)})
    ok2, state2 = @qc.get_message_state({:msg_id => strip_queue_prefix(job2)})
    ok3, state3 = @qc.get_message_state({:msg_id => strip_queue_prefix(job3)})

    assert_equal("done", state1, "Msg1 done")
    assert_equal("done", state2, "Msg2 done")
    assert_equal("run", state3, "Msg3 running")

    FileUtils.touch("test/tmp/unlock3")

    sleep(1.0)

    ok3, state3 = @qc.get_message_state({:msg_id => strip_queue_prefix(job3)})
    assert_equal("done", state3, "Msg3 done")
  end

  private

  def strip_queue_prefix(msg)
    msg.split("q/test_blocking/")[1]
  end

end
