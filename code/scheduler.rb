require 'socket'
require 'json'
require 'fcntl'
require 'fileutils'
require 'unixrack'
require 'code/hashdir'

module RQ
  class Scheduler

    def initialize(options, parent_pipe)
      @start_time = Time.now
      # Read config
      @name = "scheduler"
      @sched_path = "scheduler/"
      @rq_config_path = "./config/"
      @parent_pipe = parent_pipe
      init_socket

      @config = {}
    end

    def self.log(path, mesg)
      File.open(path + '/sched.log', "a") do |f|
        f.write("#{Process.pid} - #{Time.now} - #{mesg}\n")
      end
    end

    def self.start_process(options={})
      # nice pipes writeup
      # http://www.cim.mcgill.ca/~franco/OpSys-304-427/lecture-notes/node28.html
      child_rd, parent_wr = IO.pipe

      child_pid = fork do
        # Restore default signal handlers from those inherited from queuemgr
        Signal.trap('TERM', 'DEFAULT')
        Signal.trap('CHLD', 'DEFAULT')
        Signal.trap('HUP', 'DEFAULT')

        sched_path = "scheduler/"
        $0 = "[rq-scheduler]"
        begin
          parent_wr.close
          #child only code block
          RQ::Scheduler.log(sched_path, 'post fork')

          q = RQ::Scheduler.new(options, child_rd)
          # This should never return, it should Kernel.exit!
          # but we may wrap this instead
          RQ::Scheduler.log(sched_path, 'post new')
          while true
            sleep 60
          end
        rescue Exception
          self.log(sched_path, "Exception!")
          self.log(sched_path, $!)
          self.log(sched_path, $!.backtrace)
          raise
        end
      end

      #parent only code block
      child_rd.close

      if child_pid == nil
        parent_wr.close
        return nil
      end

      worker = Worker.new
      worker.qc = nil
      worker.name = 'scheduler'
      worker.status = 'RUNNING'
      worker.child_write_pipe = parent_wr
      worker.pid = child_pid
      worker.num_restarts = 0
      worker.options = options
      worker
    end

    def self.close_all_fds(exclude_fds)
      0.upto(1023) do |fd|
        next if exclude_fds.include? fd
        IO.new(fd).close rescue nil
      end
    end

    def init_socket
      # Show pid
      File.unlink(@sched_path + '/sched.pid') rescue nil
      File.open(@sched_path + '/sched.pid', "w") do |f|
        f.write("#{Process.pid}\n")
      end

      # Setup IPC
      File.unlink(@sched_path + '/sched.sock') rescue nil
      @sock = UNIXServer.open(@sched_path + '/sched.sock')
    end

    def log(mesg)
      File.open(@sched_path + '/sched.log', "a") do |f|
        f.write("#{Process.pid} - #{Time.now} - #{mesg}\n")
      end
    end

    def shutdown!
      log("Received shutdown")
      Process.exit! 0
    end

    def run_loop
      Signal.trap('TERM') do
        log("received TERM signal")
        shutdown!
      end

      sleep while true
    end

  end
end
