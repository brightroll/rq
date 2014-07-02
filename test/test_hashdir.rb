#!/usr/bin/env ruby
$: << File.expand_path('..', File.dirname(__FILE__))

require 'vendor/environment'
require 'fileutils'
require 'fcntl'
require 'code/hashdir'


require 'test/unit'

# Generate test data
(1..9).each {
  |day|
  (10..15).each {
    |hour|
    FileUtils.mkdir_p("./test_dirs/2010090#{day}/#{hour}/22/2010090#{day}.#{hour}22.01.123.456789")
  }
}

class TC_HashDirTest < Test::Unit::TestCase
  # def setup
  # end

  # def teardown
  # end

  def test_num_entries
    hd_num = RQ::HashDir.num_entries('./test_dirs/')
    assert_equal(54, hd_num)
  end

  def test_entries_limit
    entries = RQ::HashDir.entries('./test_dirs/', 7)
    expected = []
    expected << "20100909.1522.01.123.456789"
    expected << "20100909.1422.01.123.456789"
    expected << "20100909.1322.01.123.456789"
    expected << "20100909.1222.01.123.456789"
    expected << "20100909.1122.01.123.456789"
    expected << "20100909.1022.01.123.456789"
    expected << "20100908.1522.01.123.456789"
    assert_equal(expected, entries)
  end

  def test_entries
    entries = RQ::HashDir.entries('./test_dirs/')
    expected = []
    expected << "20100909.1522.01.123.456789"
    expected << "20100909.1422.01.123.456789"
    expected << "20100909.1322.01.123.456789"
    expected << "20100909.1222.01.123.456789"
    expected << "20100909.1122.01.123.456789"
    expected << "20100909.1022.01.123.456789"
    expected << "20100908.1522.01.123.456789"
    assert_equal(54, entries.length)
    assert_equal("20100909.1522.01.123.456789", entries[0])
    assert_equal("20100909.1422.01.123.456789", entries[1])
    assert_equal("20100901.1122.01.123.456789", entries[-2])
    assert_equal("20100901.1022.01.123.456789", entries[-1])
  end
end


