#!/usr/bin/env ruby
$: << File.expand_path('..', File.dirname(__FILE__))

require 'vendor/environment'
require 'fileutils'
require 'fcntl'
require 'code/jsonconfigfile'
require 'test/unit'

class TC_JSONConfigFileTest < Test::Unit::TestCase
  # def setup
  # end

  # def teardown
  # end

  def test_load
    config = RQ::JSONConfigFile.new('test/fixtures/jsonconfigfile/good.json')
    assert_not_nil(config.conf)
    assert_equal("1", config.conf['num_workers'])
  end

  def test_missing_initial_load
    config = RQ::JSONConfigFile.new('ZZZZZZZZtest/test_config.jsonZZZZZZZZZ')
    assert_nil(config.conf)
  end

  def test_corrupt_initial_load
    config = RQ::JSONConfigFile.new('test/fixtures/jsonconfigfile/bad.json')
    assert_nil(config.conf)
  end

  def test_config_no_change
    config = RQ::JSONConfigFile.new('test/fixtures/jsonconfigfile/good.json')
    assert_not_nil(config.conf)
    assert_equal("1", config.conf['num_workers'])

    changed = config.check_for_change
    assert_equal(RQ::JSONConfigFile::NO_CHANGE, changed)
  end

  def test_config_change_good
    test_path = 'test/fixtures/jsonconfigfile/test.json'
    good_path = 'test/fixtures/jsonconfigfile/good.json'
    good_new_path = 'test/fixtures/jsonconfigfile/good_new.json'
    bad_path = 'test/fixtures/jsonconfigfile/bad.json'

    FileUtils.rm_f(test_path)
    FileUtils.cp(good_path, test_path)

    config = RQ::JSONConfigFile.new(test_path)
    assert_not_nil(config.conf)
    assert_equal("1", config.conf['num_workers'])

    # Unamazingly, ruby cp does the wrong thing
    FileUtils.cp(good_new_path, test_path + '.tmp')
    FileUtils.mv(test_path + '.tmp', test_path)

    changed = config.check_for_change
    assert_equal(RQ::JSONConfigFile::CHANGED, changed)
    assert_equal("4", config.conf['num_workers'])

    FileUtils.rm_f(test_path)
  end

  def test_config_change_bad
    test_path = 'test/fixtures/jsonconfigfile/test.json'
    good_path = 'test/fixtures/jsonconfigfile/good.json'
    bad_path = 'test/fixtures/jsonconfigfile/bad.json'

    FileUtils.rm_f(test_path)
    FileUtils.cp(good_path, test_path)

    config = RQ::JSONConfigFile.new(test_path)
    assert_not_nil(config.conf)
    assert_equal("1", config.conf['num_workers'])

    # Unamazingly, ruby cp does the wrong thing
    FileUtils.cp(bad_path, test_path + '.tmp')
    FileUtils.mv(test_path + '.tmp', test_path)

    changed = config.check_for_change
    assert_equal(RQ::JSONConfigFile::ERROR_IGNORED, changed)
    assert_equal("1", config.conf['num_workers'])

    FileUtils.rm_f(test_path)
  end

  def test_config_change_missing
    test_path = 'test/fixtures/jsonconfigfile/test.json'
    good_path = 'test/fixtures/jsonconfigfile/good.json'
    bad_path = 'test/fixtures/jsonconfigfile/bad.json'

    FileUtils.rm_f(test_path)
    FileUtils.cp(good_path, test_path)

    config = RQ::JSONConfigFile.new(test_path)
    assert_not_nil(config.conf)
    assert_equal("1", config.conf['num_workers'])

    FileUtils.rm_f(test_path)

    changed = config.check_for_change
    assert_equal(RQ::JSONConfigFile::ERROR_IGNORED, changed)
    assert_equal("1", config.conf['num_workers'])
  end
end


