require 'socket'
require 'json'
require 'fcntl'

require 'code/queue'
require 'code/scheduler'
require 'code/web_server'
require 'version'

def log(mesg)
  File.open('log/queuemgr.log', "a") do |f|
    f.write("#{Process.pid} - #{Time.now} - #{mesg}\n")
  end
end

module RQ
  class QueueMgr

    attr_accessor :queues
    attr_accessor :scheduler
    attr_accessor :web_server
    attr_accessor :status
    attr_accessor :host
    attr_accessor :port
    attr_accessor :environment

    def initialize
      @queues = []
      @scheduler = nil
      @web_server = nil
      @start_time = Time.now
      @status = "RUNNING"
      # Read config
      @host = ""
      @port = ""
    end

    def load_config
      ENV["RQ_VER"] = VERSION_NUMBER
      ENV["RQ_SEMVER"] = SEMANTIC_VERSION_NUMBER
      ENV["RQ_ENV"] = "development"
      begin
        data = File.read('config/config.json')
        options = JSON.parse(data)
        ENV["RQ_ENV"] = options['env']
        @host = options['host']
        @port = options['port']
      rescue
        puts ""
        puts "Bad config file. Exiting"
        puts ""
        exit! 1
      end
    end

    def init
      # Show pid
      File.unlink('config/queuemgr.pid') rescue nil
      File.open('config/queuemgr.pid', "w") do |f|
        f.write("#{Process.pid}\n")
      end

      # Setup IPC
      File.unlink('config/queuemgr.sock') rescue nil
      $sock = UNIXServer.open('config/queuemgr.sock')
    end

    # Validate characters in name
    # No '.' or '/' since that could change path
    # Basically it should just be alphanum and '-' or '_'
    def valid_queue_name(name)
      nil == name.tr('/. ,;:@"(){}\\+=\'^`#~?[]%|$&<>', '*').index('*')
    end

    def queue_dirs
      Dir.entries('queue').select do |x|
        valid_queue_name x and
        File.readable? File.join('queue', x, 'config.json')
      end
    end

    def handle_request(sock)
      data, = sock.recvfrom(1024)
      cmd, arg = data.split(' ', 2)
      log("REQ [ #{cmd} #{arg} ]");

      case cmd
      when 'ping'
        sock.send("pong", 0)
        sock.close
        log("RESP [ pong ]");

      when 'environment'
        sock.send(ENV['RQ_ENV'], 0)
        sock.close
        log("RESP [ environment - #{ENV['RQ_ENV']} ]")

      when 'version'
        data = [ ENV['RQ_VER'], ENV['RQ_SEMVER'] ].to_json
        sock.send(data, 0)
        sock.close
        log("RESP [ version - #{data} ]")

      when 'queues'
        data = @queues.map { |q| q.name }.to_json
        log("RESP [ queues - #{data} ]")
        sock.send(data, 0)
        sock.close

      when 'uptime'
        data = [(Time.now - @start_time).to_i, ].to_json #['local','brserv_push'].to_json
        log("RESP [ uptime - #{data} ]")
        sock.send(data, 0)
        sock.close

      when 'restart_queue'
        log("RESP [ restart_queue - #{arg} ]")
        worker = @queues.find { |i| i.name == arg }
        status = 'fail'
        if worker.status == "RUNNING"
          Process.kill("TERM", worker.pid) rescue nil
          status = 'ok'
        else
          # TODO
          # when I have timers, do this as a message to main event loop
          # to centralize this code
          new_worker = RQ::Queue.start_process(worker.options)
          if new_worker
            log("STARTED [ #{new_worker.name} - #{new_worker.pid} ]")
            worker = new_worker
            status = 'ok'
          end
        end
        resp = [status, arg].to_json #['ok','brserv_push'].to_json
        sock.send(resp, 0)
        sock.close

      when 'create_queue'
        options = JSON.parse(arg)
        # "queue"=>{"name"=>"local", "script"=>"local.rb", "num_workers"=>"1", ...}

        if @queues.any? { |q| q.name == options['name'] }
          resp = ['fail', 'already created'].to_json
        else
          if not valid_queue_name(options['name'])
            resp = ['fail', 'queue name has invalid characters'].to_json
          else
            resp = ['fail', 'queue not created'].to_json
            worker = RQ::Queue.create(options)
            if worker
              log("create_queue STARTED [ #{worker.name} - #{worker.pid} ]")
              @queues << worker
              resp = ['success', 'queue created - awesome'].to_json
            end
          end
        end
        log("RESP [ #{resp} ]")
        sock.send(resp, 0)
        sock.close

      when 'create_queue_link'
        err = false

        begin
          options = JSON.parse(File.read(arg))
        rescue
          reason = "could not read queue config [ #{arg} ]: #{$!}"
          err = true
        end

        if not err
          err, reason = RQ::Queue.validate_options(options)
        end

        if not err
          if @queues.any? { |q| q.name == options['name'] }
            reason = 'queue is already running'
            err = true
          end
        end

        if not err
          if not valid_queue_name(options['name'])
            reason = 'queue name has invalid characters'
            err = true
          end
        end

        if not err
          worker = RQ::Queue.create(options, arg)
          log("create_queue STARTED [ #{worker.name} - #{worker.pid} ]")
          if worker
            @queues << worker
            reason = 'queue created - awesome'
            err = false
          else
            reason = 'queue not created'
            err = true
          end
        end

        resp = [ (err ? 'fail' : 'success'), reason ].to_json

        log("RESP [ #{resp} ]")
        sock.send(resp, 0)
        sock.close

      when 'delete_queue'
        worker = @queues.find { |i| i.name == arg }
        status = 'fail'
        msg = 'no such queue'
        if worker
          worker.status = "DELETE"
          Process.kill("TERM", worker.pid) rescue nil
          status = 'ok'
          msg = 'started deleting queue'
        end
        resp = [ status, msg ].to_json #['ok','brserv_push'].to_json
        sock.send(resp, 0)
        sock.close
        log("RESP [ #{resp} ]")

      else
        sock.send("ERROR", 0)
        sock.close
        log("RESP [ ERROR ] - Unhandled message")
      end
    end

    def reload
      # Stop queues whose configs have gone away
      dirs = Hash[queue_dirs.zip]

      # Notify running queues to reload configs
      @queues.each do |worker|
        if dirs.has_key? worker.name
          log("RELOAD [ #{worker.name} - #{worker.pid} ] - SENDING HUP")
          Process.kill("HUP", worker.pid) if worker.pid rescue nil
        else
          log("RELOAD [ #{worker.name} - #{worker.pid} ] - SENDING TERM")
          worker.status = "SHUTDOWN"
          Process.kill("TERM", worker.pid) if worker.pid rescue nil
        end
      end

      # Start new queues if new configs were added
      load_queues
    end

    def shutdown
      final_shutdown! if @queues.empty?

      # Remove non-running entries
      @queues.delete_if { |q| !q.pid }

      @queues.each do |q|
        q.status = "SHUTDOWN"
      end

      @queues.each do |q|
        begin
          Process.kill("TERM", q.pid) if q.pid
        rescue StandardError => e
          puts "#{q.pid} #{e.inspect}"
        end
      end
    end

    def final_shutdown!
      # Once all the queues are down, take the scheduler down
      # Process.kill("TERM", @scheduler.pid) if @scheduler.pid

      # Once all the queues are down, take the web server down
      Process.kill("TERM", @web_server) if @web_server

      # The actual shutdown happens when all procs are reaped
      File.unlink('config/queuemgr.pid') rescue nil
      $sock.close
      File.unlink('config/queuemgr.sock') rescue nil
      log("FINAL SHUTDOWN - EXITING")
      Process.exit! 0
    end

    def start_queue(name)
      worker = RQ::Queue.start_process({'name' => name})
      if worker
        @queues << worker
        log("STARTED [ #{worker.name} - #{worker.pid} ]")
      end
    end

    def start_scheduler
      worker = RQ::Scheduler.start_process
      if worker
        @scheduler = worker
        log("STARTED [ #{worker.name} - #{worker.pid} ]")
      end
    end

    def start_webserver
      @web_server = fork do
        $0 = '[rq-web]'
        config = RQ::WebServer.conf_rq_web
        RQ::WebServer.start_rq_web(config)
      end
    end

    def load_queues
      # Skip dot dirs and queues already running
      queue_dirs.each do |name|
        next if @queues.any? { |q| q.name == name }
        start_queue name
      end
    end

    def run!
      $0 = '[rq-mgr]'

      init
      load_config

      Signal.trap("TERM") do
        log("received TERM signal")
        shutdown
      end

      Signal.trap("CHLD") do
        log("received CHLD signal")
      end

      Signal.trap("HUP") do
        log("received HUP signal")
        reload
      end


      load_queues

      # TODO implement cron-like scheduler and start it up
      # start_scheduler

      start_webserver

      flag = File::NONBLOCK
      if defined?(Fcntl::F_GETFL)
        flag |= $sock.fcntl(Fcntl::F_GETFL)
      end
      $sock.fcntl(Fcntl::F_SETFL, flag)

      # Ye old event loop
      while true
        #log(queues.select { |i| i.status != "ERROR" }.map { |i| [i.name, i.child_write_pipe] }.inspect)
        io_list = queues.select { |i| i.status != "ERROR" }.map { |i| i.child_write_pipe }
        io_list << $sock
        #log(io_list.inspect)
        log('sleeping')
        begin
          ready, _, _ = IO.select(io_list, nil, nil, 60)
        rescue SystemCallError, StandardError # SystemCallError is the parent for all Errno::EFOO exceptions
          log("error on SELECT #{$!}")
          closed_sockets = io_list.delete_if { |i| i.closed? }
          log("removing closed sockets #{closed_sockets.inspect} from io_list")
          retry
        end

        next unless ready

        ready.each do |io|
          if io.fileno == $sock.fileno
            begin
              client_socket, client_sockaddr = $sock.accept
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
            # probably a child pipe that closed
            worker = queues.find do |i|
              if i.child_write_pipe
                i.child_write_pipe.fileno == io.fileno
              else
                new_worker = RQ::Queue.start_process(worker.options)
                log("STARTED [ #{new_worker.name} - #{new_worker.pid} ]")
                worker = new_worker
                false
              end
            end
            if worker
              res = Process.wait2(worker.pid, Process::WNOHANG)
              if res
                log("QUEUE PROC #{worker.name} of PID #{worker.pid} exited with status #{res[1]} - #{worker.status}")
                worker.child_write_pipe.close
                if worker.status == "RUNNING"
                  worker.num_restarts += 1
                  # TODO
                  # would really like a timer on the event loop so I can sleep a sec, but
                  # whatever
                  #
                  # If queue.rb code fails/exits
                  if worker.num_restarts >= 11
                    worker.status = "ERROR"
                    worker.pid = nil
                    worker.child_write_pipe = nil
                    log("FAILED [ #{worker.name} - too many restarts. Not restarting ]")
                  else
                    results = RQ::Queue.start_process(worker.options)
                    log("STARTED [ #{worker.options['name']} - #{results[0]} ]")
                    worker.pid = results[0]
                    worker.child_write_pipe = results[1]
                  end
                elsif worker.status == "DELETE"
                  RQ::Queue.delete(worker.name)
                  queues.delete(worker)
                  log("DELETED [ #{worker.name} ]")
                elsif worker.status == "SHUTDOWN"
                  queues.delete(worker)
                  if queues.empty?
                    final_shutdown!
                  end
                else
                  log("STRANGE: queue #{worker.pid } status = #{worker.status}")
                end
              else
                log("EXITING: queue #{worker.pid} was not ready to be reaped #{res}")
              end
            else
              log("VERY STRANGE: got a read ready on an io that we don't track!")
            end

          end
        end

      end
    end

  end
end
