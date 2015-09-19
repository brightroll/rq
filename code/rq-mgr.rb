require 'vendor/environment'
require 'daemons'

require 'code/queuemgr'

options = {
  :app_name   => 'queuemgr',
  :dir_mode   => :normal,
  :dir        => './config',
  :multiple   => false,
  :mode       => :exec,
  :backtrace  => true,
  :monitor    => false,
  :log_dir    => './log',
  :log_output => false,
}

# Daemons will chdir to / but there are many assumptions
# in code/ that it is running from the RQ basedir.
RQ_DIR = Dir.pwd

Daemons.run_proc('queuemgr', options) do
  Dir.chdir RQ_DIR

  require 'logger'
  $log = Logger.new('log/queuemgr.log')
  $log.level = Logger::INFO
  $log.progname = $0

  RQ::QueueMgr.new.run!
end
