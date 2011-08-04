#!/usr/bin/ruby

require 'fileutils'
require 'date'
require 'time'
require 'tempfile'
################################################################################
# Stuff that goes everywhere in RQ
################################################################################

Dir.glob(File.join("..", "..", "..", "..", "..", "code", "vendor", "gems", "*", "lib")).each do |lib|
  $LOAD_PATH.unshift(File.expand_path(lib))
end
Dir.glob(File.join("..", "..", "..", "..", "..")).each do |lib|
  $LOAD_PATH.unshift(File.expand_path(lib))
end

require 'rubygems'
gem_paths = [File.expand_path(File.join("..", "..", "..", "..", "..", "code", "vendor", "gems")),  Gem.default_dir]
Gem.clear_paths
Gem.send :set_paths, gem_paths.join(":")
# Setup a global binding so the GC doesn't close the file
$RQ_IO = IO.for_fd(ENV['RQ_PIPE'].to_i)

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
  log = "#{qname}/queue.log"
  if File.exists?(log)
    # move file to avoid writes to it while computing dates
    tmp_log = Tempfile.new("#{qname.split('/')[-1]}_log", Dir.getwd)
    FileUtils.mv(log, tmp_log.path)

    # read last and first line from file
    last_line = `tail -n 1 #{tmp_log.path}`
    first_line = tmp_log.open.gets

    # compute datetimes
    first = DateTime.parse(first_line.split(' - ')[1])
    last = DateTime.parse(last_line.split(' - ')[1])

    # generate timestamp extension
    ext = sprintf("%s%.2d%.2d.%.2d:%.2d-%s%.2d%.2d.%.2d:%.2d",
                  first.year, first.month, first.day, first.hour, first.min,
                  last.year, last.month, last.day, last.hour, last.min)

    puts "status: moving #{log}"
    STDOUT.flush
    FileUtils.mv(tmp_log.path, "#{log}.#{ext}")
  end
end

def remove_old(qname, days)
  clean_queues = ["/done", "/relayed", "/prep", "/queue"]
  clean_queues.each do |cq|
    if File.exists?(qname + cq)

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
  if not File.exists?queues[0]
    fail_hard("the specified queue #{queues} does not exist")
  end
end

queues.each do |q|
  rm_logs_older_than(q, "/queue.log.?*", 2*24)
  mv_logs(q)
  remove_old(q, 2)
end

write_status('done', "successfully ran this script")
