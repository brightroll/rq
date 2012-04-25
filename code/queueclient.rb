
require 'socket'
require 'json'
require 'code/unixrack'

module RQ
  class QueueClient

    attr_accessor :name
    attr_accessor :pid

    def initialize(name, path=".")
      @name = name

      path = File.join(File.dirname(__FILE__), "..")

      @queue_path = "#{path}/queue/#{@name}"
      @queue_sock_path = "#{path}/queue/#{@name}/queue.sock"
    end

    def exists?
      # TODO: do more of a test, actual round trip ping
      File.directory?(@queue_path)
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
        retry
      rescue EOFError
        #TODO: add debug mode
        #puts "Got an EOF from socket read"
        return nil
      rescue Errno::ECONNRESET,Errno::EPIPE,Errno::EINVAL,Errno::EBADF
        puts "Got an #{$!} from socket read"
        exit! 0
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

      obj = JSON.parse(result[1])

      obj
    end

    def ping
      return send_recv('ping')
    end

    def uptime
      return send_recv('uptime')
    end

    def status
      return send_recv('status')
    end

    def shutdown
      return send_recv('shutdown')
    end

    def create_message(params)
      return send_recv('create_message', params.to_json)
    end

    def single_que(params)
      return send_recv('single_que', params.to_json)
    end

    def messages(params)
      return send_recv('messages', params.to_json)
    end

    def num_messages
      return send_recv('num_messages')
    end

    def prep_message(params)
      return send_recv('prep_message', params.to_json)
    end

    def attach_message(params)
      return send_recv('attach_message', params.to_json)
    end

    def delete_attach_message(params)
      return send_recv('delete_attach_message', params.to_json)
    end

    def commit_message(params)
      return send_recv('commit_message', params.to_json)
    end

    def delete_message(params)
      return send_recv('delete_message', params.to_json)
    end

    def get_message(params)
      return send_recv('get_message', params.to_json)
    end

    def run_message(params)
      return send_recv('run_message', params.to_json)
    end

    def clone_message(params)
      return send_recv('clone_message', params.to_json)
    end

    def get_config
      return send_recv('config')
    end

  end
end

