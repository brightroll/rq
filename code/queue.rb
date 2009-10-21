
require 'socket'
require 'json'
require 'fcntl'

module RQ
  class Queue

    def initialize(options, parent_pipe)
      @start_time = Time.now
      # Read config
      @name = options['name']
      @queue_path = "queue/#{@name}"
      @parent_pipe = parent_pipe
      init_socket

      @prep   = []  # should be small
      @que    = []  # could be large
      @run    = []  # should be small
      @pause  = []  # should be small
      @done   = []  # should be large

      if load_config == false
        @config = { "opts" => options, "admin_status" => "UP", "oper_status" => "UP" }
      end

      load_messages
    end

    def self.create(options)
      # Create a directories and config
      queue_path = "queue/#{options['name']}"
      FileUtils.mkdir_p(queue_path)
      FileUtils.mkdir_p(queue_path + '/prep')
      FileUtils.mkdir_p(queue_path + '/que')
      FileUtils.mkdir_p(queue_path + '/run')
      FileUtils.mkdir_p(queue_path + '/pause')
      FileUtils.mkdir_p(queue_path + '/done')
      FileUtils.mkdir_p(queue_path + '/err')
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
          q = RQ::Queue.new(options, child_rd)
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

    def alloc_id(msg)
      # Simple time insertion system - should work since single threaded
      times = 0
      begin
        z = Time.now.getutc
        name = z.strftime("%Y%m%d.%H%M.%S.") + sprintf("%03d", (z.tv_usec / 1000))
        #fd = IO::sysopen(@queue_path + '/mesgs/' + name, Fcntl::O_WRONLY | Fcntl::O_EXCL | Fcntl::O_CREAT)
        # There we have created a name and inode
        #IO.new(fd).close

        Dir.mkdir(@queue_path + "/prep/" + name)
        @prep << name
        msg["msg_id"] = name
        return msg
      rescue
        times += 1
        if times > 10 
          log("FAILED TO ALLOC ID")
          return nil
        end
        sleep 0.001
        retry
      end
      nil  # fail
    end

    def store_msg(msg)
      # Write message to disk
      begin
        data = msg.to_json
        # Need a sysopen style system here TODO
        basename = @queue_path + "/prep/" + msg['msg_id']
        File.open(basename + '/tmp', 'w') { |f| f.write(data) }
        File.rename(basename + '/tmp', basename + '/msg')
      rescue
        log("FATAL - couldn't write message")
        return false
      end

      return true
    end

    def que(msg, from_state = 'prep')
      msg_id = msg['msg_id']
      begin
        basename = @queue_path + "/#{from_state}/" + msg_id
        return false unless File.exists? basename
        newname = @queue_path + "/que/" + msg_id
        File.rename(basename, newname)
      rescue
        log("FATAL - couldn't commit message #{msg_id}")
        log("        [ #{$!} ]")
        return false
      end

      # Put in queue
      @prep.delete(msg['msg_id'])
      @que.unshift(msg)

      # Persist queue
      # TODO
      return true
    end

    def load_messages

      # prep just has message ids
      basename = @queue_path + '/prep/'
      @prep = Dir.entries(basename).reject {|i| i.index('.') == 0 }
      @prep.sort!.reverse!

      # que has actual messages copied
      basename = @queue_path + '/que/'
      messages = Dir.entries(basename).reject {|i| i.index('.') == 0 }

      messages.sort!.reverse!

      messages.each do
        |mname|
        begin
          data = File.read(basename + mname + "/msg")
          msg = JSON.parse(data)
        rescue
          log("Bad message in queue: #{mname}")
          next
        end
        @que << msg
      end
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
        log('sleeping')
        begin
          ready = IO.select([@sock, @parent_pipe], nil, nil, 60)
        rescue Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::ECONNABORTED, Errno::EPROTO, Errno::EINTR
          log("error on SELECT #{$!}")
          retry
        end

        next unless ready

        ready[0].each do |io|
          if io.fileno == @sock.fileno
            begin
              client_socket, client_sockaddr = @sock.accept
            rescue Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::ECONNABORTED, Errno::EPROTO, Errno::EINTR
              log('error acception on main sock, supposed to be readysleeping')
            end
            # Linux Doesn't inherit and BSD does... recomended behavior is to set again 
            flag = 0xffffffff ^ File::NONBLOCK
            if defined?(Fcntl::F_GETFL)
              flag &= client_socket.fcntl(Fcntl::F_GETFL)
            end
            #log("Non Block Flag -> #{flag} == #{File::NONBLOCK}")
            client_socket.fcntl(Fcntl::F_SETFL, flag)
            handle_request(client_socket)
          else
            log("QUEUE #{@name} of PID #{Process.pid} noticed parent close exiting...")
            shutdown!
          end
        end
      end
    end


    def handle_request(sock)
      data = sock.recvfrom(1024)

      log("REQ [ #{data[0]} ]")

      if data[0].index('ping') == 0
        log("RESP [ pong ]")
        sock.send("pong", 0)
        sock.close
        return
      end
      if data[0].index('uptime') == 0
        resp = [(Time.now - @start_time).to_i, ].to_json
        log("RESP [ #{resp} ]")
        sock.send(resp, 0)
        sock.close
        return
      end

      if data[0].index('options') == 0
        resp = @config["opts"].to_json
        log("RESP [ #{resp} ]")
        sock.send(resp, 0)
        sock.close
        return
      end

      if data[0].index('status') == 0
        resp = [ @config["admin_status"], @config["oper_status"] ].to_json
        log("RESP [ #{resp} ]")
        sock.send(resp, 0)
        sock.close
        return
      end

      if data[0].index('shutdown') == 0
        resp = [ 'ok' ].to_json
        log("RESP [ #{resp} ]")
        sock.send(resp, 0)
        sock.close
        shutdown!
        return
      end

      if data[0].index('create_message') == 0
        json = data[0].split(' ', 2)[1]
        options = JSON.parse(json)

        msg = { }
        if alloc_id(msg)
          msg.merge!(options)
          store_msg(msg)
          que(msg)
          resp = [ "ok", msg['msg_id'] ].to_json
        else
          resp = [ "fail", "unknown reason"].to_json
        end
        log("RESP [ #{resp} ]")
        sock.send(resp, 0)
        sock.close
        return
      end

      if data[0].index('messages') == 0
        status = { }
        status['prep']   = @prep
        status['que']    = @que.map { |m| [m['msg_id'], m['status']] }
        status['run']    = @run.map { |m| [m['msg_id'], m['status']] }
        status['pause']  = @pause.map { |m| [m['msg_id'], m['status']] }
        status['done']   = @done.length

        resp = status.to_json
        log("RESP [ #{resp} ]")
        sock.send(resp, 0)
        sock.close
        return
      end

      sock.send('[ "ERROR" ]', 0)
      sock.close
      log("RESP [ ERROR ] - Unhandled message")
    end

  end
end


