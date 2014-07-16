require 'json'
require 'code/errors'
require 'code/protocol'

module RQ
  class QueueClient

    include Protocol

    attr_accessor :name
    attr_accessor :pid

    def initialize(name, path=".")
      @name = name

      path = File.join(File.dirname(__FILE__), "..")

      @queue_path = File.join(path, 'queue', @name)
      set_protocol_sock_path(File.join(@queue_path, 'queue.sock'))
      set_protocol_messages(PROTOCOL_MESSAGES)

      raise RQ::RqQueueNotFound unless File.directory?(@queue_path)
    end

    def running?(pid=read_pid)
      Process.kill(0, pid)
    rescue
    end

    def stop!
      pid = read_pid
      Process.kill("TERM", pid) if running?(pid)
    rescue
    end

    # on create, the file might not quite exist yet
    # this could be bad
    def read_pid
      File.read(@queue_path + '/queue.pid').to_i
    rescue Errno::ENOENT
      sleep(1.0)
      File.read(@queue_path + '/queue.pid').to_i
    end

    PROTOCOL_MESSAGES = %w{
      shutdown
      num_messages
      config
      create_message
      single_que
      messages
      prep_message
      attach_message
      delete_attach_message
      commit_message
      delete_message
      destroy_message
      get_message
      run_message
      clone_message
      get_message_state
      get_message_status
    }

    def ping
      send_recv('ping').first
    end

    def uptime
      send_recv('uptime').first
    end

    def status
      send_recv('status').first
    end

  end
end
