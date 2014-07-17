#!/usr/bin/env ruby
$: << File.expand_path('..', File.dirname(__FILE__))

require 'vendor/environment'
require 'test/unit'
require 'fileutils'
require 'code/adminoper'

class TC_AdminOperTest < Test::Unit::TestCase

  def setup
    FileUtils.rm(Dir.glob('config/test_adminoper*'), :force => true)
    @ao = RQ::AdminOper.new("config", "test_adminoper")
  end

  def teardown
    FileUtils.rm(Dir.glob('config/test_adminoper*'), :force => true)
  end


  def test_new
    assert_equal("UP", @ao.admin_status, "Admin status")
    assert_equal("UP", @ao.oper_status, "Oper status")
    assert_equal("UP", @ao.status, "Combined status")
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
    assert_equal("UP", @ao.status, "Combined status")
  end

  def test_set_down
    FileUtils.touch("config/test_adminoper.down")
    @ao.update!

    assert_equal("DOWN", @ao.admin_status, "Admin status")
    assert_equal("UP", @ao.oper_status, "Oper status")
    assert_equal("DOWN", @ao.status, "Combined status")
  end

  def test_daemon_set_error_no_update
    @ao.set_oper_status("SCRIPTERROR")

    assert_equal("UP", @ao.admin_status, "Admin status")
    assert_equal("SCRIPTERROR", @ao.oper_status, "Oper status")
    assert_equal("SCRIPTERROR", @ao.status, "Combined status")
  end

  def test_daemon_set_error2
    FileUtils.touch("config/test_adminoper.pause")

    @ao.update!
    @ao.set_oper_status("SCRIPTERROR")

    assert_equal("PAUSE", @ao.admin_status, "Admin status")
    assert_equal("SCRIPTERROR", @ao.oper_status, "Oper status")
    assert_equal("SCRIPTERROR", @ao.status, "Combined status")
  end

  def test_pause
    FileUtils.touch("config/test_adminoper.pause")

    @ao.update!
    @ao.set_oper_status("UP")

    assert_equal("PAUSE", @ao.admin_status, "Admin status")
    assert_equal("UP", @ao.oper_status, "Oper status")
    assert_equal("PAUSE", @ao.status, "Combined status")
  end

  def test_no_update
    FileUtils.touch("config/test_adminoper.pause")

    assert_equal("UP", @ao.admin_status, "Admin status")
    assert_equal("UP", @ao.oper_status, "Oper status")
    assert_equal("UP", @ao.status, "Combined status")
  end

  def test_no_update2
    FileUtils.touch("config/test_adminoper.pause")

    assert_equal("UP", @ao.admin_status, "Admin status")
    assert_equal("UP", @ao.oper_status, "Oper status")
    assert_equal("UP", @ao.status, "Combined status")

    @ao.update!

    assert_equal("PAUSE", @ao.admin_status, "Admin status")
    assert_equal("UP", @ao.oper_status, "Oper status")
    assert_equal("PAUSE", @ao.status, "Combined status")

    FileUtils.rm_rf("config/test_adminoper.pause")

    assert_equal("PAUSE", @ao.admin_status, "Admin status")
    assert_equal("UP", @ao.oper_status, "Oper status")
    assert_equal("PAUSE", @ao.status, "Combined status")
  end

  def test_multi_update
    FileUtils.touch("config/test_adminoper.pause")

    assert_equal("UP", @ao.admin_status, "Admin status")
    assert_equal("UP", @ao.oper_status, "Oper status")
    assert_equal("UP", @ao.status, "Combined status")

    @ao.update!

    assert_equal("PAUSE", @ao.admin_status, "Admin status")
    assert_equal("UP", @ao.oper_status, "Oper status")
    assert_equal("PAUSE", @ao.status, "Combined status")

    FileUtils.rm_rf("config/test_adminoper.pause")
    @ao.update!

    assert_equal("UP", @ao.admin_status, "Admin status")
    assert_equal("UP", @ao.oper_status, "Oper status")
    assert_equal("UP", @ao.status, "Combined status")
  end

  def test_multi_update_normal
    FileUtils.touch("config/test_adminoper.pause")

    assert_equal("UP", @ao.admin_status, "Admin status")
    assert_equal("UP", @ao.oper_status, "Oper status")
    assert_equal("UP", @ao.status, "Combined status")

    @ao.update!

    assert_equal("PAUSE", @ao.admin_status, "Admin status")
    assert_equal("UP", @ao.oper_status, "Oper status")
    assert_equal("PAUSE", @ao.status, "Combined status")

    @ao.set_oper_status('SCRIPTERROR')

    assert_equal("PAUSE", @ao.admin_status, "Admin status")
    assert_equal("SCRIPTERROR", @ao.oper_status, "Oper status")
    assert_equal("SCRIPTERROR", @ao.status, "Combined status")

    @ao.set_oper_status('UP')

    assert_equal("PAUSE", @ao.admin_status, "Admin status")
    assert_equal("UP", @ao.oper_status, "Oper status")
    assert_equal("PAUSE", @ao.status, "Combined status")

    FileUtils.rm_rf("config/test_adminoper.pause")
    @ao.update!

    assert_equal("UP", @ao.admin_status, "Admin status")
    assert_equal("UP", @ao.oper_status, "Oper status")
    assert_equal("UP", @ao.status, "Combined status")
  end

  def test_multi_update_error
    FileUtils.touch("config/test_adminoper.down")

    @ao.update!

    assert_equal("DOWN", @ao.admin_status, "Admin status")
    assert_equal("UP", @ao.oper_status, "Oper status")
    assert_equal("DOWN", @ao.status, "Combined status")

    @ao.set_oper_status('SCRIPTERROR')

    assert_equal("DOWN", @ao.admin_status, "Admin status")
    assert_equal("SCRIPTERROR", @ao.oper_status, "Oper status")
    assert_equal("SCRIPTERROR", @ao.status, "Combined status")

    @ao.set_oper_status('UP')

    assert_equal("DOWN", @ao.admin_status, "Admin status")
    assert_equal("UP", @ao.oper_status, "Oper status")
    assert_equal("DOWN", @ao.status, "Combined status")

    FileUtils.rm_rf("config/test_adminoper.down")
    @ao.update!

    assert_equal("UP", @ao.admin_status, "Admin status")
    assert_equal("UP", @ao.oper_status, "Oper status")
    assert_equal("UP", @ao.status, "Combined status")

    @ao.set_oper_status('SCRIPTERROR')

    assert_equal("UP", @ao.admin_status, "Admin status")
    assert_equal("SCRIPTERROR", @ao.oper_status, "Oper status")
    assert_equal("SCRIPTERROR", @ao.status, "Combined status")

    @ao.set_oper_status('UP')

    assert_equal("UP", @ao.admin_status, "Admin status")
    assert_equal("UP", @ao.oper_status, "Oper status")
    assert_equal("UP", @ao.status, "Combined status")
  end

end
