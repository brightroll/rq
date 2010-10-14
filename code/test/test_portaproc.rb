#!/usr/bin/env ruby

require 'test/unit'
require 'code/portaproc'

class TC_PortaProcTest < Test::Unit::TestCase

  def test_get_list
    ps = RQ::PortaProc.new

    ok,res = ps.get_list

    assert(ok, "Error: Couldn't run command. - #{res}")

    assert((res.length > 0), "Error: Results empty")

    assert((res[0].has_key?(:uid)), "Error: missing uid field")
    assert((res[0].has_key?(:pid)), "Error: missing pid field")
    assert((res[0].has_key?(:ppid)), "Error: missing ppid field")
    assert((res[0].has_key?(:sess)), "Error: missing sess field")
    assert((res[0].has_key?(:cmd)), "Error: missing cmd field")
  end

end

