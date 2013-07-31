require 'vendor/environment'
require 'code/queuemgrclient'

Dir.chdir(File.join(File.dirname(__FILE__), ".."))

def log(mesg)
  File.open("log/queuemgr.log", "a") do |f|
    f.write("#{Process.pid} - #{Time.now} - #{mesg}\n")
  end
end

cwd = Dir.pwd

def stop
  if RQ::QueueMgrClient.running?
    p "Stopping..."
    if RQ::QueueMgrClient.stop!
      200.times do
        break if not RQ::QueueMgrClient.running?
        sleep 0.01
      end
      p "Stopped..."
    else
      p "Error shutting down..."
    end
  else
    p "Not running. Already stopped..."
  end
end


# This method causes the current running process to become a daemon
def daemonize()
  srand # Split rand streams between spawning and daemonized process
  log('daemonize did srand')
  if fork
    log("exiting parent...")
    exit
  end

  # Detach from the controlling terminal
  unless sess_id = Process.setsid
    log('daemonize exception')
    raise RuntimeException.new('cannot detach from controlling terminal')
  end

  log("New session id = #{sess_id}")

  # Prevent the possibility of acquiring a controlling terminal
  #if oldmode.zero?
  trap 'SIGHUP', 'IGNORE'

  # Exit from the parent again, to guarantee we cannot reconnect to old
  # session
  exit if fork
  #end
  log('daemonize done forking')

  log("New session id = #{sess_id}")

  # TODO: re chdir to proper dir
  #Dir.chdir "/"   # Release old working directory
  File.umask 0027 # This will restrict file creation mode to 750 (complement of 027)

  # Make sure all file descriptors are closed
  ObjectSpace.each_object(IO) do |io|
#    unless [STDIN, STDOUT, STDERR].include?(io)
      begin
        unless io.closed?
          io.close
        end
      rescue ::Exception
        log('daemonize io close exception')
      end
#    end
  end

  #return oldmode ? sess_id : 0   # Return value is mostly irrelevant
  return sess_id
end

def start
  p "Running RQ Queue mgr daemon..."
  log("Pre daemonize")
  daemonize
  log("Did daemonize")
end

if ARGV[0] == 'start'
  start
  # daemonize forks and exits from parent
elsif (ARGV[0] == 'run' or ARGV[0] == 'debug')
  p "Staying in foreground..."
elsif (ARGV[0] == 'restart')
  p "Restarting..."
  stop
  start
  # daemonize forks and exits
elsif (ARGV[0] == 'stop')
  stop
  exit 0
end



log("Doing chdir to #{cwd}")

Dir.chdir(cwd)

$0 = '[rq-mgr]'

begin
  load 'code/queuemgr.rb'
rescue Exception
  File.open("log/queuemgr.log", "a") do |f|
    f.write("#{Process.pid} - #{Time.now} - EXCEPTION [ #{$!} ]\n")
    f.write("#{Process.pid} - #{Time.now} - EXCEPTION [ #{$!.backtrace} ]\n")
  end
end
