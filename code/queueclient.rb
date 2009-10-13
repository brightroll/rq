
require 'socket'
require 'json'

module RQ
  class QueueClient

    attr_accessor :name
    attr_accessor :pid

    def initialize(name)
      @name = name
      @queue_path = "queue/#{@name}"
      @queue_sock_path = "queue/#{@name}/queue.sock"
    end

    def exists?
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

    def messages
      client = UNIXSocket.open(@queue_sock_path)
      client.send("messages", 0)
      # TODO - deal with larger packet sizes
      result = client.recvfrom(4096)
      client.close
      result ? JSON.parse(result[0]) : nil
    end

  end
end

