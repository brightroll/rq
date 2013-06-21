#!/usr/bin/env ruby

require 'test/unit'
require 'code/htmlutils'

class TC_HtmlUtilsTest < Test::Unit::TestCase

  def test_escape_html
    assert_equal("abcd&amp;efgh", RQ::HtmlUtils.escape_html("abcd&efgh"))
    assert_equal(" &amp; ", RQ::HtmlUtils.escape_html(" & "))
    assert_equal("&amp;", RQ::HtmlUtils.escape_html("&"))
    assert_equal(" &amp;amp; ", RQ::HtmlUtils.escape_html(" &amp; "))

    assert_equal("abcd&lt;efgh", RQ::HtmlUtils.escape_html("abcd<efgh"))
    assert_equal(" &lt; ", RQ::HtmlUtils.escape_html(" < "))
    assert_equal("&lt;", RQ::HtmlUtils.escape_html("<"))
    assert_equal(" &amp;lt; ", RQ::HtmlUtils.escape_html(" &lt; "))

    assert_equal("abcd&gt;efgh", RQ::HtmlUtils.escape_html("abcd>efgh"))
    assert_equal(" &gt; ", RQ::HtmlUtils.escape_html(" > "))
    assert_equal("&gt;", RQ::HtmlUtils.escape_html(">"))
    assert_equal(" &amp;gt; ", RQ::HtmlUtils.escape_html(" &gt; "))

    assert_equal("&lt;&amp;&gt;/\\'\"", RQ::HtmlUtils.escape_html("<&>/\\'\""))
  end

  def test_linkify_text
    url = "http://link.to/me"
    assert_equal("<a href='#{url}'>http://link.to/me</a>", RQ::HtmlUtils.linkify_text(url))
    assert_equal("abcd\n\n A <a href='#{url}'>http://link.to/me</a> Z\n&efgh", RQ::HtmlUtils.linkify_text("abcd\n\n A #{url} Z\n&efgh"))
  end

  def test_ansi_to_html
    attr = 0
    fg = 32
    txt = "\033[#{fg}m #{fg}  \033[0m"
    assert_equal("<span style='color:rgb(0, 187, 0)'> #{fg}  </span>", RQ::HtmlUtils.ansi_to_html(txt))

    attr = 0
    fg = 32
    txt = "\033[#{attr};#{fg}m #{fg}  \033[0m"
    assert_equal("<span style='color:rgb(0, 187, 0)'> #{fg}  </span>", RQ::HtmlUtils.ansi_to_html(txt))

    attr = 1
    fg = 32
    txt = "\033[#{attr};#{fg}m #{fg}  \033[0m"
    assert_equal("<span style='color:rgb(0, 255, 0)'> #{fg}  </span>", RQ::HtmlUtils.ansi_to_html(txt))

    attr = 1
    fg = 33
    bg = 42
    txt = "\033[#{attr};#{bg};#{fg}m #{attr};#{bg};#{fg}  \033[0m"
    assert_equal("<span style='color:rgb(255, 255, 85);background-color:rgb(0, 187, 0)'> #{attr};#{bg};#{fg}  </span>", RQ::HtmlUtils.ansi_to_html(txt))

    fg = 32
    bg = 42
    txt = "\n \033[#{fg}m #{fg}  \033[0m \n  \033[#{bg}m #{bg}  \033[0m \n  zipper "
    assert_equal("\n <span style='color:rgb(0, 187, 0)'> #{fg}  </span> \n  <span style='background-color:rgb(0, 187, 0)'> #{bg}  </span> \n  zipper ", RQ::HtmlUtils.ansi_to_html(txt))
  end

end

