
require 'socket'
require 'json'

module RQ
  class QueueMgrClient

    def self.running?
      pid = self.read_pid

      return false unless pid

      begin
        Process.kill(0, pid)
      rescue
        return false
      end

      return true
    end
    
    def self.stop!
      if self.running?
        pid = self.read_pid
        begin
          Process.kill("TERM", pid)
          return true
        rescue
          return false
        end
      end
      return false
    end
    
    def self.read_pid
      File.read('config/queuemgr.pid').to_i rescue nil
    end
    
    def self.ping
      client = UNIXSocket.open('config/queuemgr.sock')
      client.send("ping", 0)
      result = client.recvfrom(1024)
      client.close
      return result ? result[0] : nil
    end

    def self.environment
      client = UNIXSocket.open('config/queuemgr.sock')
      client.send("environment", 0)
      result = client.recvfrom(1024)
      client.close
      return result ? result[0] : nil
    end
    
    def self.version
      client = UNIXSocket.open('config/queuemgr.sock')
      client.send("version", 0)
      result = client.recvfrom(1024)
      client.close
      return result ? result[0] : nil
    end

    def self.queues
      client = UNIXSocket.open('config/queuemgr.sock')
      client.send("queues", 0)
      result = client.recvfrom(1024)
      client.close
      p result
      result ? JSON.parse(result[0]) : nil
    end

    def self.uptime
      client = UNIXSocket.open('config/queuemgr.sock')
      client.send("uptime", 0)
      result = client.recvfrom(1024)
      client.close
      result ? JSON.parse(result[0]) : nil
    end

    def self.create_queue(params)
      json_params = params.to_json
      client = UNIXSocket.open('config/queuemgr.sock')
      client.send("create_queue #{json_params}", 0)
      result = client.recvfrom(1024)
      client.close
      p result
      result ? JSON.parse(result[0]) : nil
    end

  end
end

