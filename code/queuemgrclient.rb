require 'json'
require 'code/protocol'

module RQ
  class QueueMgrClient
    include Protocol

    def initialize
      set_protocol_sock_path('config/queuemgr.sock')
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

    def queues
      send_recv('queues')
    end

    def create_queue(params)
      send_recv('create_queue', params.to_json)
    end

    # TODO: json params
    def create_queue_link(json_path)
      send_recv('create_queue_link', json_path)
    end

    # TODO: json params
    def restart_queue(queue_name)
      send_recv('restart_queue', queue_name)
    end

    # TODO: json params
    def delete_queue(queue_name)
      send_recv('delete_queue', queue_name)
    end

  end
end
