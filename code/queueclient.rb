require 'vendor/environment'
require 'socket'
require 'json'
require 'unixrack'
require 'code/errors'

module RQ
  class QueueClient

    attr_accessor :name
    attr_accessor :pid

    def initialize(name, path=".")
      @name = name

      path = File.join(File.dirname(__FILE__), "..")

      @queue_path = File.join(path, 'queue', @name)
      @queue_sock_path = File.join(@queue_path, 'queue.sock')

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

    def do_read(client, numr = 32768)
      begin
        dat = client.sysread(numr)
      rescue Errno::EINTR  # Ruby threading can cause an alarm/timer interrupt on a syscall
        sleep 0.001 # A tiny pause to prevent consuming all CPU
        retry
      rescue EOFError
        #TODO: add debug mode
        #puts "Got an EOF from socket read"
        return nil
      rescue Errno::ECONNRESET,Errno::EPIPE,Errno::EINVAL,Errno::EBADF
        raise "Got an #{$!} from socket read"
      end
      dat
    end

    # msg is single word, data is assumbed to be content as json
    def send_recv(msg, data="")
      client = UNIXSocket.open(@queue_sock_path)

      contents = "#{msg} #{data}"
      sock_msg = sprintf("rq1 %08d %s", contents.length, contents)

      UnixRack::Socket.write_buff(client, sock_msg)

      protocol = do_read(client, 4)

      if protocol != 'rq1 '
        raise "Invalid Protocol - Expecting 'rq1 ' got: #{protocol}"
      end

      size_str = do_read(client, 9)

      if size_str[-1..-1] != " "
        raise "Invalid Protocol"
      end

      size = size_str.to_i

      result = UnixRack::Socket.read_sock_num_bytes(client, size, lambda {|s| puts s})

      if result[0] == false
        return ["fail", result[1]]
      end

      client.close

      JSON.parse(result[1])
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

    def create_message(params)
      send_recv('create_message', params.to_json)
    end

    def single_que(params)
      send_recv('single_que', params.to_json)
    end

    def messages(params)
      send_recv('messages', params.to_json)
    end

    def num_messages
      send_recv('num_messages')
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

    def get_config
      send_recv('config')
    end

    def get_message_state(params)
      send_recv('get_message_state', params.to_json)
    end

    def get_message_status(params)
      send_recv('get_message_status', params.to_json)
    end

  end
end
