#!/usr/bin/env ruby
$: << File.expand_path('..', File.dirname(__FILE__))

require 'test/unit'
require 'fileutils'
require 'code/adminoper'

class TC_AdminOperTest < Test::Unit::TestCase
  def setup
    @ao = RQ::AdminOper.new("config/test_adminoper")
  end

  def teardown
    FileUtils.rm(Dir.glob('config/test_adminoper*'), :force => true)
    @ao = nil
  end


  def test_new
    assert_equal("UNKNOWN", @ao.admin_status, "Admin status")
    assert_equal("UNKNOWN", @ao.oper_status, "Oper status")
  end

  def test_bad_path
    assert_raise ArgumentError do
      RQ::AdminOper.new("configXXXXXXXXXXXX/test_adminoper")
    end
  end

  def test_nofile
    @ao.update!

    assert_equal("UP", @ao.admin_status, "Admin status")
    assert_equal("UP", @ao.oper_status, "Oper status")
  end

  def test_set_down
    FileUtils.touch("config/test_adminoper.down")
    @ao.update!

    assert_equal("DOWN", @ao.admin_status, "Admin status")
    assert_equal("DOWN", @ao.oper_status, "Oper status")
  end

  def test_daemon_set_error_no_update
    @ao.set_daemon_status("SCRIPTERROR")

    assert_equal("UNKNOWN", @ao.admin_status, "Admin status")
    assert_equal("SCRIPTERROR", @ao.oper_status, "Oper status")
  end

  def test_daemon_set_error2
    FileUtils.touch("config/test_adminoper.pause")

    @ao.update!
    @ao.set_daemon_status("SCRIPTERROR")

    assert_equal("PAUSE", @ao.admin_status, "Admin status")
    assert_equal("SCRIPTERROR", @ao.oper_status, "Oper status")
  end

  def test_pause
    FileUtils.touch("config/test_adminoper.pause")

    @ao.update!

    assert_equal("PAUSE", @ao.admin_status, "Admin status")
    assert_equal("PAUSE", @ao.oper_status, "Oper status")
  end

  def test_no_update
    FileUtils.touch("config/test_adminoper.pause")

    assert_equal("UNKNOWN", @ao.admin_status, "Admin status")
    assert_equal("UNKNOWN", @ao.oper_status, "Oper status")
  end

  def test_no_update2
    FileUtils.touch("config/test_adminoper.pause")

    assert_equal("UNKNOWN", @ao.admin_status, "Admin status")
    assert_equal("UNKNOWN", @ao.oper_status, "Oper status")

    @ao.update!

    assert_equal("PAUSE", @ao.admin_status, "Admin status")
    assert_equal("PAUSE", @ao.oper_status, "Oper status")

    FileUtils.rm_rf("config/test_adminoper.pause")

    assert_equal("PAUSE", @ao.admin_status, "Admin status")
    assert_equal("PAUSE", @ao.oper_status, "Oper status")
  end

  def test_multi_update
    FileUtils.touch("config/test_adminoper.pause")

    assert_equal("UNKNOWN", @ao.admin_status, "Admin status")
    assert_equal("UNKNOWN", @ao.oper_status, "Oper status")

    @ao.update!

    assert_equal("PAUSE", @ao.admin_status, "Admin status")
    assert_equal("PAUSE", @ao.oper_status, "Oper status")

    FileUtils.rm_rf("config/test_adminoper.pause")
    @ao.update!

    assert_equal("UP", @ao.admin_status, "Admin status")
    assert_equal("UP", @ao.oper_status, "Oper status")
  end

  def test_multi_update_normal
    FileUtils.touch("config/test_adminoper.pause")

    assert_equal("UNKNOWN", @ao.admin_status, "Admin status")
    assert_equal("UNKNOWN", @ao.oper_status, "Oper status")

    @ao.update!

    assert_equal("PAUSE", @ao.admin_status, "Admin status")
    assert_equal("PAUSE", @ao.oper_status, "Oper status")

    @ao.set_daemon_status('SCRIPTERROR')

    assert_equal("PAUSE", @ao.admin_status, "Admin status")
    assert_equal("SCRIPTERROR", @ao.oper_status, "Oper status")

    @ao.set_daemon_status('UP')

    assert_equal("PAUSE", @ao.admin_status, "Admin status")
    assert_equal("PAUSE", @ao.oper_status, "Oper status")

    FileUtils.rm_rf("config/test_adminoper.pause")
    @ao.update!

    assert_equal("UP", @ao.admin_status, "Admin status")
    assert_equal("UP", @ao.oper_status, "Oper status")
  end

  def test_multi_update_error
    FileUtils.touch("config/test_adminoper.down")

    @ao.update!

    assert_equal("DOWN", @ao.admin_status, "Admin status")
    assert_equal("DOWN", @ao.oper_status, "Oper status")

    @ao.set_daemon_status('SCRIPTERROR')

    assert_equal("DOWN", @ao.admin_status, "Admin status")
    assert_equal("SCRIPTERROR", @ao.oper_status, "Oper status")

    @ao.set_daemon_status('UP')

    assert_equal("DOWN", @ao.admin_status, "Admin status")
    assert_equal("DOWN", @ao.oper_status, "Oper status")

    FileUtils.rm_rf("config/test_adminoper.down")
    @ao.update!

    assert_equal("UP", @ao.admin_status, "Admin status")
    assert_equal("UP", @ao.oper_status, "Oper status")

    @ao.set_daemon_status('SCRIPTERROR')

    assert_equal("UP", @ao.admin_status, "Admin status")
    assert_equal("SCRIPTERROR", @ao.oper_status, "Oper status")

    @ao.set_daemon_status('UP')

    assert_equal("UP", @ao.admin_status, "Admin status")
    assert_equal("UP", @ao.oper_status, "Oper status")
  end

end

