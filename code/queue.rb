
require 'socket'
require 'json'

module RQ
  class Queue

    def initialize(options)
      @start_time = Time.now
      # Read config
      @queue_path = "queue/#{options['name']}"
      init_socket

      if load_config == false
        @config = { "opts" => options, "admin_status" => "UP", "oper_status" => "UP" }
      end
    end

    def self.create(options)
      # Create a directories and config
      queue_path = "queue/#{options['name']}"
      FileUtils.mkdir_p(queue_path)
      FileUtils.mkdir_p(queue_path + '/mesgs')
      # Write config to dir
      File.open(queue_path + '/config.json', "w") do
        |f|
        f.write(options.to_json)
      end
      RQ::Queue.start_process(options)
    end

    def self.log(path, mesg)
      File.open(path + '/queue.log', "a") do
        |f|
        f.write("#{Process.pid} - #{Time.now} - #{mesg}\n")
      end
    end

    def self.start_process(options)
      # nice pipes writeup
      # http://www.cim.mcgill.ca/~franco/OpSys-304-427/lecture-notes/node28.html
      child_rd, parent_wr = IO.pipe
      
      child_pid = fork do
        queue_path = "queue/#{options['name']}"
        $0 = "[rq] [#{options['name']}]"
        begin
          parent_wr.close
          #child only code block
          RQ::Queue.log(queue_path, 'post fork')
          
          # Unix house keeping
          self.close_all_fds([child_rd.fileno])
          # TODO: probly some other signal, session, proc grp, etc. crap
          
          RQ::Queue.log(queue_path, 'post close_all')
          q = RQ::Queue.new(options)
          # This should never return, it should Kernel.exit!
          # but we may wrap this instead
          RQ::Queue.log(queue_path, 'post new')
          q.run_loop
        rescue
          self.log(queue_path, $!)
          self.log(queue_path, $!.backtrace)
          raise
        end
      end

      #parent only code block
      child_rd.close

      if child_pid == nil
        parent_wr.close
        return nil
      end

      [child_pid, parent_wr]
    end

    def self.close_all_fds(exclude_fds)
      0.upto(1023) do |fd|
        begin
          next if exclude_fds.include? fd 
          if io = IO::new(fd)
            io.close
          end
        rescue
        end
      end
    end

    def init_socket
      # Show pid
      File.unlink(@queue_path + '/queue.pid') rescue nil
      File.open(@queue_path + '/queue.pid', "w") do
        |f|
        f.write("#{Process.pid}\n")
      end

      # Setup IPC
      File.unlink(@queue_path + '/queue.sock') rescue nil
      @sock = UNIXServer.open(@queue_path + '/queue.sock')
    end

    def load_config
      begin
        data = File.read(@queue_path + '/queue.config')
        @config = JSON.parse(data)
      rescue
        return false
      end
      return true
    end

    def write_config
      begin
        data = @config.to_json
        File.open(@queue_path + '/queue.config.tmp', 'w') { |f| f.write(data) }
        File.rename(@queue_path + '/queue.config.tmp', @queue_path + '/queue.config')
      rescue
        log("FATAL - couldn't write config")
        return false
      end
      return true
    end

    def log(mesg)
      File.open(@queue_path + '/queue.log', "a") do
        |f|
        f.write("#{Process.pid} - #{Time.now} - #{mesg}\n")
      end
    end

    def shutdown!
      log("Received shutdown")
      write_config
      Process.exit! 0
    end

    def run_loop

      Signal.trap("TERM") do
        log("received TERM signal")
        shutdown!
      end

      # Keep this here, cruft loves crufty company
      require 'fcntl'
      flag = File::NONBLOCK
      if defined?(Fcntl::F_GETFL)
        flag |= @sock.fcntl(Fcntl::F_GETFL)
      end
      @sock.fcntl(Fcntl::F_SETFL, flag)

      while true
        begin
          # old way, not so friendly... too much hidden
          # better to use the new way (which depends on Fcntl above)
          # client_socket, client_sockaddr = @sock.accept_nonblock
          client_socket, client_sockaddr = @sock.accept
        rescue Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::ECONNABORTED, Errno::EPROTO, Errno::EINTR
          log('sleeping')
          # TODO: self-pipe 'trick' coming soon
          IO.select([@sock], nil, nil, 60)
          retry
        end

        # Linux Doesn't inherit and BSD does... recomended behavior is to set again 
        flag = 0xffffffff ^ File::NONBLOCK
        if defined?(Fcntl::F_GETFL)
          flag &= client_socket.fcntl(Fcntl::F_GETFL)
        end
        #log("Non Block Flag -> #{flag} == #{File::NONBLOCK}")
        client_socket.fcntl(Fcntl::F_SETFL, flag)
        handle_request(client_socket)
      end
    end


    def handle_request(sock)
      data = sock.recvfrom(1024)

      log("REQ [ #{data[0]} ]")

      if data[0].index('ping')
        log("RESP [ pong ]")
        sock.send("pong", 0)
        sock.close
        return
      end
      if data[0].index('uptime')
        resp = [(Time.now - @start_time).to_i, ].to_json
        log("RESP [ #{resp} ]")
        sock.send(resp, 0)
        sock.close
        return
      end

      if data[0].index('options')
        resp = @config["opts"].to_json
        log("RESP [ #{resp} ]")
        sock.send(resp, 0)
        sock.close
        return
      end

      if data[0].index('status')
        resp = [ @config["admin_status"], @config["oper_status"] ].to_json
        log("RESP [ #{resp} ]")
        sock.send(resp, 0)
        sock.close
        return
      end

      if data[0].index('shutdown')
        resp = [ 'ok' ].to_json
        log("RESP [ #{resp} ]")
        sock.send(resp, 0)
        sock.close
        shutdown!
        return
      end

      sock.send("ERROR", 0)
      sock.close
      log("RESP [ ERROR ] - Unhandled message")
    end

  end
end


