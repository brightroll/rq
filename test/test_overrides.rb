#!/usr/bin/env ruby
$: << File.expand_path('..', File.dirname(__FILE__))

require 'vendor/environment'
require 'test/unit'
require 'code/overrides'

class TC_OverridesTest < Test::Unit::TestCase

  def test_no_file
    ps = RQ::Overrides.new('blah')

    assert(ps.show_field("non-existant"), "Error: show_field was not true")
    assert(ps.show_field("mesg_param1"), "Error: show_field was not true")

    assert_equal("no change at all", ps.text("non-existant", 'help', "no change at all"), "Error: text override not correct")
    assert_equal("no change at all", ps.text("mesg_param1", 'help', "no change at all"), "Error: text override not correct")
    assert_equal("no change at all", ps.text("mesg_param1", 'blart', "no change at all"), "Error: text override not correct")
  end

  def test_all_hidden
    ps = RQ::Overrides.new('blah', false)
    ps.data = { 'default' => "hidden" }

    assert_equal(false, ps.show_field("non-existant"), "Error: show_field was not false")
    assert_equal(false, ps.show_field("mesg_param1"), "Error: show_field was not false")

    assert_equal("no change at all", ps.text("non-existant", 'help', "no change at all"), "Error: text override not correct")
    assert_equal("no change at all", ps.text("mesg_param1", 'help', "no change at all"), "Error: text override not correct")
    assert_equal("no change at all", ps.text("mesg_param1", 'blart', "no change at all"), "Error: text override not correct")
  end

  def test_some_hidden
    ps = RQ::Overrides.new('blah', false)
    ps.data = { "default" => 'hidden',
      'mesg_param1' => {'not-real' => 'not-real'}}

    assert_equal(false, ps.show_field("non-existant"), "Error: show_field was not false")
    assert_equal(true, ps.show_field("mesg_param1"), "Error: show_field was not true")

    assert_equal("no change at all", ps.text("non-existant", 'help', "no change at all"), "Error: text override not correct")
    assert_equal("no change at all", ps.text("mesg_param1", 'help', "no change at all"), "Error: text override not correct")
    assert_equal("no change at all", ps.text("mesg_param1", 'blart', "no change at all"), "Error: text override not correct")

    assert_equal("not-real", ps.text("mesg_param1", 'not-real', "not-real"), "Error: text override not correct for 'mesg_param1', 'not-real'")
  end

  def test_some_not_hidden_overriden
    ps = RQ::Overrides.new('blah', false)
    ps.data = { 'mesg_param1' => {'not-real' => 'not-real'}}

    assert_equal(true, ps.show_field("non-existant"), "Error: show_field was not true")
    assert_equal(true, ps.show_field("mesg_param1"), "Error: show_field was not true")

    assert_equal("no change at all", ps.text("non-existant", 'help', "no change at all"), "Error: text override not correct")
    assert_equal("no change at all", ps.text("mesg_param1", 'help', "no change at all"), "Error: text override not correct")
    assert_equal("no change at all", ps.text("mesg_param1", 'blart', "no change at all"), "Error: text override not correct")

    assert_equal("not-real", ps.text("mesg_param1", 'not-real', "not-real"), "Error: text override not correct for 'mesg_param1', 'not-real'")
  end

end

