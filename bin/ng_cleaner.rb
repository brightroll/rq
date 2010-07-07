#!/usr/bin/env ruby
# == Synopsis
#
# Clean up done or relayed queues from processed RQ messages.
# By default this is performed on all queues.
#
# == Usage
#
# ng_cleaner.rb [OPTIONS] 
#
# Either a thresh, hour or percent option must be specified
#
#
# -h, --help:
#    show help
#
# --percent <INT>, -p <INT>
#    Clean out a percentage of the messages
#    eg ng_cleaner.rb -p 75   will remove 25 percent of the mesages
#
# --hours <INT>, -H <INT>
#    Clean out any messages older than X hours
#
# --thresh <INT>, -t <INT>
#    Remove all messages over this threshold
#    eg ng_cleaner.rb -t 7000 removed all messages older than the first 7000
#
# --queue <QUENAME>, -q <QUENAME>
#    Perform the removal on only a single queue
#    default is all queues are processed
#
#
# --dry-run <1>, -d <1>
#    Do not perform the actual delete, just print out those that would have been removed
#

require 'getoptlong'
require 'fileutils'
require 'rdoc/usage'
@@rqpath = "/rq/current/queue.noindex/"


def getargs
  myops = {}
  opts = GetoptLong.new(
    ['--help', '-h', GetoptLong::NO_ARGUMENT],
    ['--percent', '-p', GetoptLong::OPTIONAL_ARGUMENT],
    ['--hours', '-H', GetoptLong::OPTIONAL_ARGUMENT],
    ['--thresh', '-t', GetoptLong::OPTIONAL_ARGUMENT],
    ['--queue', '-q', GetoptLong::OPTIONAL_ARGUMENT],
    ['--dry-run', '-d', GetoptLong::OPTIONAL_ARGUMENT]
  )
  opts.each do |opt, arg|
    case opt
      when '--help'
        RDoc::usage
        exit(0)
      when '--percent'
        myops['percent'] = arg.to_i
      when '--hours'
        myops['hours'] = arg.to_i
      when '--thresh'
        myops['thresh'] = arg.to_i
      when '--queue'
        myops['queue'] = arg
      when '--dry-run'
        myops['dry'] = arg
    end
  end
  if myops.length < 1
    RDoc::usage
    exit(1)
  end
  myops
end

def just_list(qname, regex)
  if File.exists?(@@rqpath + qname + "/done") and qname != "relay"
    done_dir = "/done"
  elsif File.exists?(@@rqpath + qname + "/relayed")
    done_dir = "/relayed"
  else
    puts "cannot figure out what to do"
    exit(1)
  end
  files = Dir.glob(@@rqpath + qname + done_dir + "/#{regex}").sort{|a,b| File.mtime(b) <=> File.mtime(a)}
  files
end

def find_older_than(qname, regex, hours)
  files = []
  if File.exists?(@@rqpath + qname + "/done")
    done_dir = "/done"
  elsif File.exists?(@@rqpath + qname + "/relayed")
    done_dir = "/relayed"
  else
    puts "cannot figure out what to do"
    exit(1)
  end
  Dir.glob(@@rqpath + qname + done_dir + "/#{regex}").each do |f|
    if (Time.now-File.mtime(f))/3600 > hours
      files << f
    end
  end
  files
end

def list_queues
  ques = []
  Dir.glob(@@rqpath + "/*/config.json" ).each do |q|
    q =~ /.*\/(\S+)\/config\.json/
      ques << $1
  end
  ques
end

opts = getargs
if opts.has_key?"queue"
  clean_queues = [opts['queue']]
else
  clean_queues = list_queues
end

clean_queues.each do |q|
  if opts.has_key?"hours"
    del_list = find_older_than(q, "2*", opts['hours'])
  elsif opts.has_key?"percent"
    del_list = just_list(q, "2*")
    del_list = del_list[(del_list.length*(opts["percent"]/100.0)).to_i .. -1]
  elsif opts.has_key?"thresh"
    del_list = just_list(q, "2*")
    del_list = del_list[opts['thresh'] .. -1]
  else
    RDoc::usage
    exit(1)
  end
  if opts.has_key?"dry"
    begin
      del_list.each {|d| puts d}
    rescue NoMethodError
      ignore = 1
    rescue Exception => e
      puts e.inspect
      exit(1)
    end
  else
    begin
      del_list.each {|d| FileUtils.rm_rf(d)}
    rescue NoMethodError
      ignore = 1
    rescue Exception => e
      puts e.inspect
      exit(1)
    end
  end
end

