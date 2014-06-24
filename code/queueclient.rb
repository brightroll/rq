require 'vendor/environment'
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

    def ping
      send_recv('ping').first
    end

    def uptime
      send_recv('uptime').first
    end

    def status
      send_recv('status')
    end

    def shutdown
      send_recv('shutdown')
    end

    def num_messages
      send_recv('num_messages')
    end

    def get_config
      send_recv('config')
    end

    def create_message(params)
      send_recv('create_message', params.to_json)
    end

    def single_que(params)
      send_recv('single_que', params.to_json)
    end

    def messages(params)
      send_recv('messages', params.to_json)
    end

    def prep_message(params)
      send_recv('prep_message', params.to_json)
    end

    def attach_message(params)
      send_recv('attach_message', params.to_json)
    end

    def delete_attach_message(params)
      send_recv('delete_attach_message', params.to_json)
    end

    def commit_message(params)
      send_recv('commit_message', params.to_json)
    end

    def delete_message(params)
      send_recv('delete_message', params.to_json)
    end

    def get_message(params)
      send_recv('get_message', params.to_json)
    end

    def run_message(params)
      send_recv('run_message', params.to_json)
    end

    def clone_message(params)
      send_recv('clone_message', params.to_json)
    end

    def get_message_state(params)
      send_recv('get_message_state', params.to_json)
    end

    def get_message_status(params)
      send_recv('get_message_status', params.to_json)
    end

  end
end
