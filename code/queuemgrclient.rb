require 'json'
require 'code/protocol'

module RQ
  class QueueMgrClient
    include Protocol

    def initialize
      set_protocol_sock_path('config/queuemgr.sock')
      set_protocol_messages(PROTOCOL_MESSAGES)
    end

    def running?
      pid = read_pid

      return false unless pid

      begin
        Process.kill(0, pid)
      rescue
        return false
      end

      return true
    end

    def stop!
      if running?
        pid = read_pid
        begin
          Process.kill("TERM", pid)
          return true
        rescue
          return false
        end
      end
      return false
    end

    def read_pid
      File.read('config/queuemgr.pid').to_i rescue nil
    end

    PROTOCOL_MESSAGES = %w{
      queues
      create_queue
      create_queue_link
      up_queue
      down_queue
      pause_queue
      resume_queue
      restart_queue
      delete_queue
    }

    def ping
      send_recv('ping').first
    end

    def environment
      send_recv('environment').first
    end

    def version
      send_recv('version').first
    end

    def uptime
      send_recv('uptime').first
    end

  end
end
