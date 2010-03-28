
require 'socket'
require 'json'

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

    def running?
      pid = read_pid
      begin
        Process.kill(0, pid)
        return true
      rescue
        return false
      end
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
      File.read(@queue_path + '/queue.pid').to_i
    end
    
    def ping
      client = UNIXSocket.open(@queue_sock_path)
      client.send("ping", 0)
      result = client.recvfrom(1024)
      client.close
      return result ? result[0] : nil
    end
    
    def uptime
      client = UNIXSocket.open(@queue_sock_path)
      client.send("uptime", 0)
      result = client.recvfrom(1024)
      client.close
      result ? JSON.parse(result[0]) : nil
    end

    def options
      client = UNIXSocket.open(@queue_sock_path)
      client.send("options", 0)
      result = client.recvfrom(1024)
      client.close
      result ? JSON.parse(result[0]) : nil
    end

    def status
      client = UNIXSocket.open(@queue_sock_path)
      client.send("status", 0)
      result = client.recvfrom(1024)
      client.close
      result ? JSON.parse(result[0]) : nil
    end

    def shutdown
      client = UNIXSocket.open(@queue_sock_path)
      client.send("shutdown", 0)
      result = client.recvfrom(1024)
      client.close
      result ? JSON.parse(result[0]) : nil
    end

    def create_message(params)
      json_params = params.to_json
      client = UNIXSocket.open(@queue_sock_path)
      client.send("create_message #{json_params}", 0)
      result = client.recvfrom(1024)
      client.close
      result ? JSON.parse(result[0]) : nil
    end

    def single_que(params)
      json_params = params.to_json
      client = UNIXSocket.open(@queue_sock_path)
      client.send("single_que #{json_params}", 0)
      result = client.recvfrom(1024)
      client.close
      result ? JSON.parse(result[0]) : nil
    end

    def do_read(client)
      begin
        dat = client.sysread(16384)
      rescue EOFError
        puts "Got an EOF from socket read"
        return nil
      rescue Errno::ECONNRESET,Errno::EPIPE,Errno::EINVAL,Errno::EBADF
        puts "Got an #{$!} from socket read"
        exit! 0
      end
    end

    def messages
      client = UNIXSocket.open(@queue_sock_path)
      client.send("messages", 0)
      result = []
      while true
         r = do_read(client)
         if r != nil
           result << r
         else
           break
         end
      end
      client.close
      result ? JSON.parse(result.join('')) : nil
    end

    def prep_message(params)
      json_params = params.to_json
      client = UNIXSocket.open(@queue_sock_path)
      client.send("prep_message #{json_params}", 0)
      result = client.recvfrom(1024)
      client.close
      result ? JSON.parse(result[0]) : nil
    end

    def attach_message(params)
      json_params = params.to_json
      client = UNIXSocket.open(@queue_sock_path)
      client.send("attach_message #{json_params}", 0)
      result = client.recvfrom(1024)
      client.close
      result ? JSON.parse(result[0]) : nil
    end

    def commit_message(params)
      json_params = params.to_json
      client = UNIXSocket.open(@queue_sock_path)
      client.send("commit_message #{json_params}", 0)
      result = client.recvfrom(1024)
      client.close
      result ? JSON.parse(result[0]) : nil
    end

    def delete_message(params)
      json_params = params.to_json
      client = UNIXSocket.open(@queue_sock_path)
      client.send("delete_message #{json_params}", 0)
      result = client.recvfrom(1024)
      client.close
      result ? JSON.parse(result[0]) : nil
    end

    def get_message(params)
      json_params = params.to_json
      client = UNIXSocket.open(@queue_sock_path)
      client.send("get_message #{json_params}", 0)
      result = client.recvfrom(1024)
      client.close
      result ? JSON.parse(result[0]) : nil
    end

    def clone_message(params)
      json_params = params.to_json
      client = UNIXSocket.open(@queue_sock_path)
      client.send("clone_message #{json_params}", 0)
      result = client.recvfrom(1024)
      client.close
      result ? JSON.parse(result[0]) : nil
    end
  end
end

