#!/usr/bin/env ruby
$:.unshift(File.join(File.dirname(__FILE__), ".."))

require 'vendor/environment'
require 'fileutils'
require 'date'
require 'time'
require 'code/hashdir'

# Setup a global binding so the GC doesn't close the file
$RQ_IO = IO.for_fd(ENV['RQ_WRITE'].to_i)

# IO tower to RQ mgr process
def write_status(state, mesg = '')
  msg = "#{state} #{mesg}\n"

  STDOUT.write("#{Process.pid} - #{Time.now} - #{msg}")
  STDOUT.flush
  $RQ_IO.syswrite(msg)
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

def fail_hard(mesg)
  write_status('fail', mesg)
  exit(1)
end

################################################################################
# Start the real work here
################################################################################

def listq(basedir)
  queues = Dir.glob(basedir + "/queue/??*")
  queues
end

def rm_logs_older_than(qname, regex, hours)
  Dir.glob(qname + "/#{regex}").each do |f|
    if (Time.now-File.mtime(f))/3600 > hours
      begin
        puts "status: removing #{f}"
        STDOUT.flush
        FileUtils.rm_rf(f)
      rescue Exception => e
        puts e.inspect
        STDOUT.flush
        exit(1)
      end
    end
  end
end

def mv_logs(qname)
  if File.exist?("#{qname}/queue.log")
    a=Time.now
    b = sprintf("%s%.2d%.2d.%.2d:%.2d" ,a.year, a.month, a.day, a.hour, a.min)
    puts "status: moving #{qname}/queue.log"
    STDOUT.flush
    FileUtils.mv("#{qname}/queue.log", "#{qname}/queue.log.#{b}")
  end
end

def remove_old(qname, days)
  clean_queues = ["/done", "/relayed", "/prep", "/queue"]
  clean_queues.each do |cq|
    if File.exist?(qname + cq)
  
      # go by directories and remove any day dir > days + 1
      # then go into the hour dirs and remove by time
      # easier to whack a whole higher level dir then stat everything below it
      
      Dir.glob(qname + cq + "/????????").each do |x|
        if Date.today - Date.strptime(File.basename(x), "%Y%m%d") >= days + 1
          puts "status: removing " + x
          STDOUT.flush
          FileUtils.rm_rf(x)
        elsif Date.today - Date.strptime(File.basename(x), "%Y%m%d") == days
          Dir.glob(qname + cq + "/????????/??").each do |y|
            if y =~ /(\d{8})\/(\d{2})$/
              timstr = $1 + "."+ $2 + ":00:00"
              j= DateTime.now - DateTime.strptime(timstr, "%Y%m%d.%H:%M:%S")
              if j.to_i >= days
                puts "status: removing " + y
                STDOUT.flush
                FileUtils.rm_rf(y)
              end
            end
          end
        end
      end
    end
  end
  
end
  
def trim_relay(qpath, num)
  puts "Trimming Relay to #{num} entries"
  STDOUT.flush

  all_msgs = RQ::HashDir.entries(qpath + "/relayed")

  msgs = all_msgs[num..-1]

  if msgs == nil
    puts "relay relayed is under #{num} entries"
    STDOUT.flush
    return
  end

  msgs.each do |ent|
    path = RQ::HashDir.path_for(qpath, 'relayed', ent)
    puts "status: removing " + path
    STDOUT.flush
    FileUtils.rm_rf(path)
  end

  puts "status: removed #{msgs.length} entries from relayed"
  STDOUT.flush
end


##################################################################
# My MAIN
##################################################################
basedir = "/rq/current"

if not ENV.has_key?("RQ_PARAM1")
  fail_hard("need to specify a PARAM1")
end

if ENV['RQ_PARAM1'] == "ALLQUEUES"
  queues = listq(basedir)
else
  queues = [basedir + "/queue/" + ENV['RQ_PARAM1']]
  if not File.exist?queues[0]
    fail_hard("the specified queue #{queues} does not exist")
  end
end

log_days = 2
if ENV['RQ_PARAM2'] && ENV['RQ_PARAM2'].match(/\d/)
  log_days = $&.to_i
  puts "OVERRIDE: log_age to #{log_days} days"
  STDOUT.flush
end
queues.each do |q|
  rm_logs_older_than(q, "/queue.log.?*", log_days*24)
  mv_logs(q)
  remove_old(q, log_days)
end

trim_relay(basedir + "/queue/relay", 60000)

write_status('done', "successfully ran this script")
