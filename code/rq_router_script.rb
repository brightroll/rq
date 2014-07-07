#!/usr/bin/env ruby
$:.unshift(File.join(File.dirname(__FILE__), ".."))

require 'vendor/environment'
require 'code/rule_processor'
require 'json'

module Alarm
  case RUBY_VERSION.to_f
    when 1.8
      require 'dl/import'
      extend DL::Importable
    when 1.9
      require 'dl/import'
      extend DL::Importer
    else # 2.0+
      require 'fiddle/import'
      extend Fiddle::Importer
  end
  if RUBY_PLATFORM =~ /darwin/
    so_ext = 'dylib'
  else
    so_ext = 'so.6'
  end
  dlload "libc.#{so_ext}"
  extern "unsigned int alarm(unsigned int)"
end


$rq_msg_dir = Dir.pwd
Dir.chdir("#{File.dirname(__FILE__)}")

# Setup a global binding so the GC doesn't close the file
$RQ_IO = IO.for_fd(ENV['RQ_WRITE'].to_i)
$RQ_RESULT_IO = IO.for_fd(ENV['RQ_READ'].to_i)

# IO tower to RQ mgr process
def write_status(state, mesg)
  msg = "#{state} #{mesg}\n"

  STDOUT.write("#{Process.pid} - #{Time.now} - #{msg}")
  $RQ_IO.syswrite(msg)
end

def read_status()
  data = $RQ_RESULT_IO.sysread(512)
  data.split(' ', 2)
end

def handle_fail(mesg = 'soft fail')
  count = ENV['RQ_COUNT'].to_i

  if count > 15
    write_status('run', "RQ_COUNT > 15 - failing")
    write_status('fail', "RQ_COUNT > 15 - failing")
    exit(0)
  end

  wait_seconds = count * count * 60
  write_status('resend', "#{wait_seconds}-#{mesg}")
  exit(0)
end

def main
  path = "../config/rq_router_rules.rb"
  rp = RQ::RuleProcessor.process_pathname(path)

  if rp == nil
    File.open("../config/rq_router.down", "w") { |f| f.write("bad rules file") }
    write_status('err', "Bad rule file at: #{path}")
    exit 1
  end

  trap("ALRM") { puts "#{$$}: program took too long (60 secs). Goodbye"; $stdout.flush; exit! 2  }
  Alarm.alarm(60)

  # Read current message
  data = File.read("#{$rq_msg_dir}/../msg")  # TODO: eliminate this cheat
  curr_msg = JSON.parse(data)

  rule = rp.first_match(curr_msg)

  if rule.data[:log]
    File.open("../log/rq_router.log", "a") do
      |f|
      f.write("#{Process.pid} - #{Time.now} - #{rule.data[:desc]} - #{rule.data[:action].to_s} - #{curr_msg['msg_id']} - #{curr_msg['src']}\n")
    end
  end

  if rule.data[:delay] > 0
    write_status('run', "router delay #{rule.data[:delay]} seconds")
    sleep rule.data[:delay]
  end

  if rule.data[:action] == :done
    write_status('done', "router processed a done")
    exit 0
  end

  if rule.data[:action] == :err
    write_status('err', "router processed an err")
    exit 1
  end

  if rule.data[:action] == :balance
    host = rule.select_hosts()[0]
    new_dest = rp.txform_host(curr_msg['dest'], host)
    write_status('dup', "0-X-#{new_dest}")
    status, new_id = read_status()
    if status == 'ok'
      write_status('done', "DUP to #{new_id}")
      exit 0
    else
      write_status('err', "DUP failed - #{new_id}")
      exit 1
    end
  end

  if rule.data[:action] == :relay
    hosts = rule.select_hosts()

    hosts.each {
      |h|
      new_dest = rp.txform_host(curr_msg['dest'], h)
      write_status('dup', "0-X-#{new_dest}")

      status, new_id = read_status()
      if status == 'ok'
        write_status('run', "DUP relay to #{new_id}")
      else
        write_status('err', "DUP relay failed - #{new_id}")
        exit 1
      end
    }

    write_status('done', "done relay of #{hosts.length} messages")
    exit 0
  end
end

main()
