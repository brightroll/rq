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

class TC_WebOverridesTest < Test::Unit::TestCase
  def setup
    @rq_port = (ENV['RQ_PORT'] || 3333).to_i
  end

  def teardown
    FileUtils.rm_f('queue/test/form.json')
  end

  def test_web_form_not_hidden
    uri_str = "http://127.0.0.1:#{@rq_port}/q/test/new_message"
    res = Net::HTTP.get_response(URI.parse(uri_str))
    assert_equal("200", res.code)
    result = res.body

    doc = Nokogiri::HTML(result)

    # Verify that all elements are hidden

    flds = doc.css("div.field")
    submit = flds.pop

    flds.each { | fld |
      assert_nil(fld['style'])
    }
  end

  def test_web_form_hidden
    File.open('queue/test/form.json', 'w') { |f|
      f.write('{ "default" : "hidden" }')
    }

    uri_str = "http://127.0.0.1:#{@rq_port}/q/test/new_message"
    res = Net::HTTP.get_response(URI.parse(uri_str))
    assert_equal("200", res.code)
    result = res.body

    doc = Nokogiri::HTML(result)

    # Verify that all elements are hidden

    flds = doc.css("div.field")
    submit = flds.pop

    flds.each { | fld |
      assert_equal('display: none;', fld['style'])
    }
  end

  def test_web_form_overriden
    File.open('queue/test/form.json', 'w') { |f|
      f.write('{ "default" : "hidden" ,')
      f.write('  "mesg_param1" : {') 
      f.write('     "label" : "Cluster ID", ') 
      f.write('     "help" : "The unique cluster identifier in cyclops" ') 
      f.write('  },')
      f.write('  "mesg_param3" : {') 
      f.write('     "label" : "Branch", ') 
      f.write('     "help" : "Branch to push to this cluster when it is ready" ') 
      f.write('  }')
      f.write('}')
    }

    uri_str = "http://127.0.0.1:#{@rq_port}/q/test/new_message"
    res = Net::HTTP.get_response(URI.parse(uri_str))
    assert_equal("200", res.code)
    result = res.body

    doc = Nokogiri::HTML(result)

    # Verify that all elements are hidden

    flds = doc.css("div.field")
    submit = flds.pop

    flds.each { | fld |
      if 'mesg_param1_field' == fld['id']
        assert_nil(fld['style'])
        assert_equal("Cluster ID", fld.at_css('label').inner_text)
        assert_equal("The unique cluster identifier in cyclops", fld.at_css('p.note').inner_text)
      elsif 'mesg_param3_field' == fld['id']
        assert_nil(fld['style'])
        assert_equal("Branch", fld.at_css('label').inner_text)
        assert_equal("Branch to push to this cluster when it is ready", fld.at_css('p.note').inner_text)
      else
        assert_equal('display: none;', fld['style'])
      end
    }
  end

end

