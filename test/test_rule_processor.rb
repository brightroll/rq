#!/usr/bin/env ruby
$: << File.expand_path('..', File.dirname(__FILE__))

require 'vendor/environment'
require 'test/unit'
require 'code/rule_processor'

class TC_RuleProcessorTest < Test::Unit::TestCase

  # helper
  def rule_attrib_test(rule, attrib, expected)
    assert_equal(expected,
                 rule.data[attrib],
                 "Rule #{rule.data[:num]}:#{rule.data[:desc]} - should have matched #{attrib}")
  end


  def test_good_list
    rp = RQ::RuleProcessor.process_pathname('test/fixtures/good_rules.rb')

    assert(rp, "Error: rules should have been a valid return for good_rules.rb file")

    assert_equal(6, rp.length, "Error: Rules empty")
  end

  def test_good_no_default_list
    rp = RQ::RuleProcessor.process_pathname('test/fixtures/good_no_default_rules.rb')

    assert(rp, "Error: rules should have been a valid return for good_rules.rb file")

    assert_equal(2, rp.length, "Error: Rules empty")

    msg = {'dest' => 'http://m0.btrll.com/q/old_queue_name'}
    rule = rp.first_match(msg)
    assert_equal(rp.rules[0], rule, "should have matched proper rule")

    assert_equal("default", rp.rules[1].data[:desc], "should have proper default rule")
    assert_equal(:err, rp.rules[1].data[:action], "should have proper default rule action")
    assert_equal(true, rp.rules[1].data[:log], "should have proper default rule logging")

    new_host = rp.txform_host(msg['dest'], rule.data[:route][0])
    assert_equal("http://mc34.btrll.com:3333/q/new_queue_name", new_host, "should have proper transform")
  end

  def test_good_match_rule1
    rp = RQ::RuleProcessor.process_pathname('test/fixtures/good_rules.rb')

    num = 0
    res = rp.rules[num].match({'dest' => 'http://xyz.abc.com/barrier_process_err'})
    assert_equal(true, res, "Rule #{num + 1} - should have matched message")

    res = rp.rules[num].match({'dest' => 'http://xyz.abc.com/barrier_process_err2'})
    assert_equal(false, res, "Rule #{num + 1} - should not have matched message")

    res = rp.rules[num].match({'dest' => 'http://rpt03.btrll.com/flarby'})
    assert_equal(false, res, "Rule #{num + 1} - should not have matched message")
  end

  def test_good_attribs_rule1
    rp = RQ::RuleProcessor.process_pathname('test/fixtures/good_rules.rb')

    num = 0
    rule_attrib_test(rp.rules[num], :desc, "[mirror_processing_of_errors_with_delay]")
    rule_attrib_test(rp.rules[num], :src, nil)
    rule_attrib_test(rp.rules[num], :dest, /\/barrier_process_err$/)
    rule_attrib_test(rp.rules[num], :action, :relay)
    rule_attrib_test(rp.rules[num], :route, ["brxlog-be-halb01.btrll.com", "stats.btrll.com"])
    rule_attrib_test(rp.rules[num], :log, false)
    rule_attrib_test(rp.rules[num], :delay, 10)
  end

  def test_good_match_rule2
    rp = RQ::RuleProcessor.process_pathname('test/fixtures/good_rules.rb')

    num = 1
    res = rp.rules[num].match({'src' => 'http://barrier00.btrll.com:3333/abc'})
    assert_equal(true, res, "Rule #{num + 1} - should have matched message")

    res = rp.rules[num].match({'src' => 'http://barrier02.btrll.com:3333/a'})
    assert_equal(true, res, "Rule #{num + 1} - should have matched message")

    res = rp.rules[num].match({'src' => 'http://barrier1.btrll.com:3333/a'})
    assert_equal(false, res, "Rule #{num + 1} - should not have matched message")

    res = rp.rules[num].match({'src' => 'http://barrier2.btrll.com:3333/a'})
    assert_equal(false, res, "Rule #{num + 1} - should not have matched message")

    res = rp.rules[num].match({'src' => 'http://rpt8.btrll.com/flarby'})
    assert_equal(false, res, "Rule #{num + 1} - should not have matched message")
  end

  def test_good_attribs_rule2
    rp = RQ::RuleProcessor.process_pathname('test/fixtures/good_rules.rb')

    num = 1
    rule_attrib_test(rp.rules[num], :desc, "[even_numbers_relay_host0]")
    rule_attrib_test(rp.rules[num], :src, /^http:\/\/barrier\d[02468]\.btrll\.com:3333/)
    rule_attrib_test(rp.rules[num], :dest, nil)
    rule_attrib_test(rp.rules[num], :action, :done)
    rule_attrib_test(rp.rules[num], :route, ["host0.btrll.com"])
    rule_attrib_test(rp.rules[num], :log, true)
    rule_attrib_test(rp.rules[num], :delay, 0)
  end

  def test_good_match_rule3
    rp = RQ::RuleProcessor.process_pathname('test/fixtures/good_rules.rb')

    num = 2
    res = rp.rules[num].match({'src' => 'http://barrier03.btrll.com:3333/a'})
    assert_equal(true, res, "Rule #{num + 1} - should have matched message")

    res = rp.rules[num].match({'src' => 'http://barrier1.btrll.com:3333/a'})
    assert_equal(false, res, "Rule #{num + 1} - should not have matched message")

    res = rp.rules[num].match({'src' => 'http://barrier02.btrll.com:3333/a'})
    assert_equal(false, res, "Rule #{num + 1} - should not have matched message")

    res = rp.rules[num].match({'src' => 'http://rpt8.btrll.com/flarby'})
    assert_equal(false, res, "Rule #{num + 1} - should not have matched message")
  end

  def test_good_attribs_rule3
    rp = RQ::RuleProcessor.process_pathname('test/fixtures/good_rules.rb')

    num = 2
    rule_attrib_test(rp.rules[num], :desc, "[odd_numbers_relay_host1]")
    rule_attrib_test(rp.rules[num], :src, /^http:\/\/barrier\d[13579]\.btrll\.com:3333/)
    rule_attrib_test(rp.rules[num], :dest, nil)
    rule_attrib_test(rp.rules[num], :action, :relay)
    rule_attrib_test(rp.rules[num], :route, 
                     [["brxlog-be-halb01.btrll.com", "brxlog-be-halb02.btrll.com",],
                       ["stats1.btrll.com", "stats2.btrll.com"]])
    rule_attrib_test(rp.rules[num], :log, false)
    rule_attrib_test(rp.rules[num], :delay, 0)
  end

  def test_good_match_rule4
    rp = RQ::RuleProcessor.process_pathname('test/fixtures/good_rules.rb')

    num = 3
    res = rp.rules[num].match({'dest' => 'http://barrier03.btrll.com:3333/a',
                           'src' => 'checkin_v1'})
    assert_equal(true, res, "Rule #{num + 1} - should have matched message")

    res = rp.rules[num].match({'dest' => 'http://barrier02.btrll.com:3333/a',
                           'src' => 'checkin_v2'})
    assert_equal(false, res, "Rule #{num + 1} - should not have matched message")

    res = rp.rules[num].match({'dest' => 'http://barrier2.btrll.com:3333/a',
                           'src' => 'checkin_v1'})
    assert_equal(false, res, "Rule #{num + 1} - should not have matched message")

    res = rp.rules[num].match({'dest' => 'http://barrier01.btrll.com:3333/a',
                           'src' => 'checkin_v2'})
    assert_equal(false, res, "Rule #{num + 1} - should not have matched message")

    res = rp.rules[num].match({'src' => 'checkin_v1'})
    assert_equal(false, res, "Rule #{num + 1} - should not have matched message")

    res = rp.rules[num].match({'dest' => 'http://barrier0.btrll.com:3333/a'})
    assert_equal(false, res, "Rule #{num + 1} - should not have matched message")

    res = rp.rules[num].match({'dest' => 'http://barrier1.btrll.com:3333/a'})
    assert_equal(false, res, "Rule #{num + 1} - should not have matched message")

    res = rp.rules[num].match({'dest' => 'http://barrier02.btrll.com:3333/a'})
    assert_equal(false, res, "Rule #{num + 1} - should not have matched message")

    res = rp.rules[num].match({'dest' => 'http://rpt8.btrll.com/flarby'})
    assert_equal(false, res, "Rule #{num + 1} - should not have matched message")
  end

  def test_good_attribs_rule4
    rp = RQ::RuleProcessor.process_pathname('test/fixtures/good_rules.rb')

    num = 3
    rule_attrib_test(rp.rules[num], :desc, "[traffic_relay_host1]")
    rule_attrib_test(rp.rules[num], :src, /^checkin_v1$/)
    rule_attrib_test(rp.rules[num], :dest, /^http:\/\/barrier\d[13579]\.btrll\.com:3333/)
    rule_attrib_test(rp.rules[num], :action, :balance)
    rule_attrib_test(rp.rules[num], :route, ["brxlog-be-halb01.btrll.com", "stats.btrll.com"])
    rule_attrib_test(rp.rules[num], :log, false)
    rule_attrib_test(rp.rules[num], :delay, 0)
  end

  def test_good_match_rule5
    rp = RQ::RuleProcessor.process_pathname('test/fixtures/good_rules.rb')

    num = 4
    res = rp.rules[num].match({'dest' => 'http://host.btrll.com:3333/old_rq_route'})
    assert_equal(true, res, "Rule #{num + 1} - should have matched message")

    res = rp.rules[num].match({'dest' => 'http://host1.btrll.com:3333/'})
    assert_equal(false, res, "Rule #{num + 1} - should not have matched message")

    res = rp.rules[num].match({'dest' => 'http://barrier1.btrll.com:3333/a'})
    assert_equal(false, res, "Rule #{num + 1} - should not have matched message")

    res = rp.rules[num].match({'dest' => 'http://barrier02.btrll.com:3333/a'})
    assert_equal(false, res, "Rule #{num + 1} - should not have matched message")

    res = rp.rules[num].match({'dest' => 'http://rpt8.btrll.com/flarby'})
    assert_equal(false, res, "Rule #{num + 1} - should not have matched message")
  end

  def test_good_attribs_rule5
    rp = RQ::RuleProcessor.process_pathname('test/fixtures/good_rules.rb')

    num = 4
    rule_attrib_test(rp.rules[num], :desc, "[old_data_center_route]")
    rule_attrib_test(rp.rules[num], :src, nil)
    rule_attrib_test(rp.rules[num], :dest, /^http:\/\/host\.btrll\.com:3333/)
    rule_attrib_test(rp.rules[num], :action, :relay)
    rule_attrib_test(rp.rules[num], :route, ["http://host1.btrll.com:3333/q/foobar"])
    rule_attrib_test(rp.rules[num], :log, true)
    rule_attrib_test(rp.rules[num], :delay, 0)
  end

  def test_good_match_rule6
    rp = RQ::RuleProcessor.process_pathname('test/fixtures/good_rules.rb')

    num = 5
    res = rp.rules[num].match({'dest' => 'http://barrier0.btrll.com:3333/a'})
    assert_equal(true, res, "Rule #{num + 1} - should have matched message")

    res = rp.rules[num].match({'dest' => 'http://barrier1.btrll.com:3333/a'})
    assert_equal(true, res, "Rule #{num + 1} - should not have matched message")

    res = rp.rules[num].match({})
    assert_equal(true, res, "Rule #{num + 1} - should have matched message")

    res = rp.rules[num].match({'src' => 'blahblah'})
    assert_equal(true, res, "Rule #{num + 1} - should have matched message")
  end

  def test_good_attribs_rule6
    rp = RQ::RuleProcessor.process_pathname('test/fixtures/good_rules.rb')

    num = 5
    rule_attrib_test(rp.rules[num], :desc, "default")
    rule_attrib_test(rp.rules[num], :src, nil)
    rule_attrib_test(rp.rules[num], :dest, nil)
    rule_attrib_test(rp.rules[num], :action, :err)
    rule_attrib_test(rp.rules[num], :route, [])
    rule_attrib_test(rp.rules[num], :log, true)
    rule_attrib_test(rp.rules[num], :delay, 0)
  end

  def test_good_first_match
    rp = RQ::RuleProcessor.process_pathname('test/fixtures/good_rules.rb')

    rule = rp.first_match({'dest' => 'http://m0.btrll.com/barrier_process_err'})
    assert_equal(rp.rules[0], rule, "should have matched proper rule")

    rule = rp.first_match({'src' => 'http://barrier08.btrll.com:3333/render'})
    assert_equal(rp.rules[1], rule, "should have matched proper rule")

    rule = rp.first_match({'src' => 'http://barrier05.btrll.com:3333/render'})
    assert_equal(rp.rules[2], rule, "should have matched proper rule")

    rule = rp.first_match({'dest' => 'http://barrier05.btrll.com:3333/render',
                           'src' => 'checkin_v1'})
    assert_equal(rp.rules[3], rule, "should have matched proper rule")

    rule = rp.first_match({'dest' => 'http://host.btrll.com:3333/render'})
    assert_equal(rp.rules[4], rule, "should have matched proper rule")

    rule = rp.first_match({'dest' => 'http://x5.btrll.com:3333/review',
                           'src' => 'qa01'})
    assert_equal(rp.rules[5], rule, "should have matched proper rule")

  end

  def test_good_host_selection
    rp = RQ::RuleProcessor.process_pathname('test/fixtures/good_rules.rb')

    RQ::Rule::rand_func = lambda {|x| 0 }

    rule = rp.rules[0]
    rule.select_hosts
    assert_equal(["brxlog-be-halb01.btrll.com", "stats.btrll.com"], rule.select_hosts, "should have selected proper hosts")

    rule = rp.rules[1]
    rule.select_hosts
    assert_equal(["host0.btrll.com"], rule.select_hosts, "should have selected proper hosts")

    RQ::Rule::rand_func = lambda {|x| 1 }

    rule = rp.rules[2]
    rule.select_hosts
    assert_equal(["brxlog-be-halb02.btrll.com", "stats2.btrll.com"], rule.select_hosts, "should have selected proper hosts")

    rule = rp.rules[3]
    rule.select_hosts
    assert_equal(["stats.btrll.com"], rule.select_hosts, "should have selected proper hosts")

    RQ::Rule::rand_func = lambda {|x| 0 }

    rule = rp.rules[4]
    rule.select_hosts
    assert_equal(["http://host1.btrll.com:3333/q/foobar"], rule.select_hosts, "should have selected proper hosts")

    rule = rp.rules[5]
    rule.select_hosts
    assert_equal([], rule.select_hosts, "should have selected proper hosts")
  end

  def test_host_transform
    rp = RQ::RuleProcessor.process_pathname('test/fixtures/good_rules.rb')

    new_host = rp.txform_host("http://oldhost.btrll.com:3333/q/box_que", "brxlog-be-halb02.btrll.com")
    assert_equal("http://brxlog-be-halb02.btrll.com:3333/q/box_que", new_host, "should have proper transform")

    new_host = rp.txform_host("http://oldhost.btrll.com/q/box_que", "brxlog-be-halb02.btrll.com")
    assert_equal("http://brxlog-be-halb02.btrll.com:3333/q/box_que", new_host, "should have proper transform")

    new_host = rp.txform_host("http://oldhost.btrll.com/q/box_que", "brxlog-be-halb02.btrll.com:2222")
    assert_equal("http://brxlog-be-halb02.btrll.com:2222/q/box_que", new_host, "should have proper transform")

    new_host = rp.txform_host("http://oldhost.btrll.com:3333/q/box_que", "brxlog-be-halb02.btrll.com:2222")
    assert_equal("http://brxlog-be-halb02.btrll.com:2222/q/box_que", new_host, "should have proper transform")

    new_host = rp.txform_host("http://oldhost.btrll.com:3333/q/box_que", "stats2.btrll.com")
    assert_equal("http://stats2.btrll.com:3333/q/box_que", new_host, "should have proper transform")

    new_host = rp.txform_host("ftp_cleaner", "stats2.btrll.com")
    assert_equal("http://stats2.btrll.com:3333/q/ftp_cleaner", new_host, "should have proper transform")

    new_host = rp.txform_host("ftp_cleaner", "http://host1.btrll.com:3333/q/foobar")
    assert_equal("http://host1.btrll.com:3333/q/foobar", new_host, "should have proper transform")

    new_host = rp.txform_host("http://oldhost.btrll.com:3333/q/box_que", "http://host1.btrll.com:3333/q/foobar")
    assert_equal("http://host1.btrll.com:3333/q/foobar", new_host, "should have proper transform")
  end

  def test_bad_list
    rp = RQ::RuleProcessor.process_pathname('test/fixtures/bad_rules.rb')

    assert_nil(rp, "Should have been nil for bad rules file")

    rp = RQ::RuleProcessor.process_pathname('test/fixtures/non_existant_rules.rb')

    assert_nil(rp, "Should have been nil for bad rules file")
  end

end

