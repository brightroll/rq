require 'socket'
require 'json'
require 'unixrack'

require 'code/main'
require 'code/queue'
require 'code/protocol'
require 'version'

module RQ
  class QueueMgr
    include Protocol

    def initialize
      @queues = { } # Hash of queue name => RQ::Queue object
      @queue_errs = Hash.new(0) # Hash of queue name => count of restarts, default 0
      @web_server = nil
      @start_time = Time.now
    end

    def load_config
      begin
        data = File.read('config/config.json')
        @config = JSON.parse(data)
        ENV["RQ_ENV"] = @config['env']
      rescue
        $log.error("Bad config file. Exiting")
        exit! 1
      end

      if @config['tmpdir']
        dir = File.expand_path(@config['tmpdir'])
        if File.directory?(dir) and File.writable?(dir)
          # This will affect the class Tempfile, which is used by Rack
          ENV['TMPDIR'] = dir
        else
          $log.error("Bad 'tmpdir' in config json [#{dir}]. Exiting")
          exit! 1
        end
      end

      @config
    end

    def init
      # Show pid
      File.unlink('config/queuemgr.pid') rescue nil
      File.open('config/queuemgr.pid', "w") do |f|
        f.write("#{Process.pid}\n")
      end

      # Setup IPC
      File.unlink('config/queuemgr.sock') rescue nil
      @sock = UNIXServer.open('config/queuemgr.sock')
    end

    # Validate characters in name
    # No '.' or '/' since that could change path
    # Basically it should just be alphanum and '-' or '_'
    def valid_queue_name(name)
      return false unless name
      return false unless name.length > 0
      nil == name.tr('/. ,;:@"(){}\\+=\'^`#~?[]%|$&<>', '*').index('*')
    end

    def queue_dirs
      Dir.entries('queue').select do |x|
        valid_queue_name x and
        File.readable? File.join('queue', x, 'config.json')
      end
    end

    def handle_request(sock)
      packet = read_packet(sock) rescue nil
      return unless packet

      cmd, arg = packet.split(' ', 2)
      $log.debug("REQ [ #{cmd} #{arg} ]")

      case cmd
      when 'ping'
        resp = [ 'pong' ].to_json
        send_packet(sock, resp)

      when 'environment'
        resp = [ ENV['RQ_ENV'] ].to_json
        send_packet(sock, resp)

      when 'version'
        resp = [ RQ_VER ].to_json
        send_packet(sock, resp)

      when 'queues'
        resp = @queues.keys.to_json
        send_packet(sock, resp)

      when 'uptime'
        resp = [(Time.now - @start_time).to_i, ].to_json
        send_packet(sock, resp)

      when 'down_queue'
        if valid_queue_name(arg) && queue = @queues[arg]
          status = RQ::AdminOper.new('config', arg)
          if status.set_admin_status('DOWN')
            resp = ['ok', arg].to_json
          else
            resp = ['fail', 'not allowed to up'].to_json
          end
        else
          resp = ['fail', 'invalid queue name'].to_json
        end
        send_packet(sock, resp)

      when 'up_queue'
        if valid_queue_name(arg) && queue = @queues[arg]
          status = RQ::AdminOper.new('config', arg)
          if status.set_admin_status('UP')
            resp = ['ok', arg].to_json
          else
            resp = ['fail', 'not allowed to up'].to_json
          end
        else
          resp = ['fail', 'invalid queue name'].to_json
        end
        send_packet(sock, resp)

      when 'pause_queue'
        if valid_queue_name(arg) && queue = @queues[arg]
          status = RQ::AdminOper.new('config', arg)
          if status.set_admin_status('PAUSE')
            resp = ['ok', arg].to_json
          else
            resp = ['fail', 'not allowed to up'].to_json
          end
        else
          resp = ['fail', 'invalid queue name'].to_json
        end
        send_packet(sock, resp)

      when 'resume_queue'
        if valid_queue_name(arg) && queue = @queues[arg]
          status = RQ::AdminOper.new('config', arg)
          if status.set_admin_status('RESUME')
            resp = ['ok', arg].to_json
          else
            resp = ['fail', 'not allowed to up'].to_json
          end
        else
          resp = ['fail', 'invalid queue name'].to_json
        end
        send_packet(sock, resp)

      when 'restart_queue'
        stop_queue(arg)
        # Reset the error count because the queue was manually restarted
        @queue_errs.delete(arg)
        sleep(0.001)
        start_queue(arg)

        resp = ['ok', arg].to_json
        send_packet(sock, resp)

      when 'create_queue'
        options = JSON.parse(arg)
        # "queue"=>{"name"=>"local", "script"=>"local.rb", "num_workers"=>"1", ...}

        if @queues.has_key?(options['name'])
          resp = ['fail', 'already created'].to_json
        else
          if not valid_queue_name(options['name'])
            resp = ['fail', 'queue name has invalid characters'].to_json
          else
            resp = ['fail', 'queue not created'].to_json
            worker = RQ::Queue.create(options)
            if worker
              $log.info("create_queue STARTED [ #{worker.name} - #{worker.pid} ]")
              @queues[worker.name] = worker
              resp = ['success', 'queue created - awesome'].to_json
            end
          end
        end
        send_packet(sock, resp)

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
          if @queues.has_key?(options['name'])
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
          $log.info("create_queue STARTED [ #{worker.name} - #{worker.pid} ]")
          if worker
            @queues[worker.name] = worker
            reason = 'queue created - awesome'
            err = false
          else
            reason = 'queue not created'
            err = true
          end
        end

        resp = [ (err ? 'fail' : 'success'), reason ].to_json
        send_packet(sock, resp)

      when 'delete_queue'
        worker = @queues[arg]
        if worker
          worker.status = "DELETE"
          Process.kill("TERM", worker.pid) rescue nil
          status = 'ok'
          msg = 'started deleting queue'
        else
          status = 'fail'
          msg = 'no such queue'
        end
        resp = [ status, msg ].to_json
        send_packet(sock, resp)

      else
        resp = [ 'error' ].to_json
        send_packet(sock, resp)
      end
    end

    def reload
      # Stop queues whose configs have gone away
      dirs = Hash[queue_dirs.zip]

      # Notify running queues to reload configs
      @queues.values.each do |worker|
        if dirs.has_key? worker.name
          $log.info("RELOAD [ #{worker.name} - #{worker.pid} ] - SENDING HUP")
          Process.kill("HUP", worker.pid) if worker.pid rescue nil
        else
          $log.info("RELOAD [ #{worker.name} - #{worker.pid} ] - SENDING TERM")
          worker.status = "SHUTDOWN"
          Process.kill("TERM", worker.pid) if worker.pid rescue nil
        end
      end

      # Start new queues if new configs were added
      load_queues
    end

    def shutdown!
      final_shutdown! if @queues.empty?

      # Remove non-running entries
      @queues.delete_if { |n, q| !q.pid }

      @queues.each do |n, q|
        q.status = "SHUTDOWN"

        begin
          Process.kill("TERM", q.pid) if q.pid
        rescue StandardError => e
          puts "#{q.pid} #{e.inspect}"
        end
      end
    end

    def final_shutdown!
      # Once all the queues are down, take the web server down
      Process.kill("TERM", @web_server) if @web_server

      # The actual shutdown happens when all procs are reaped
      File.unlink('config/queuemgr.pid') rescue nil
      @sock.close
      File.unlink('config/queuemgr.sock') rescue nil
      $log.info("FINAL SHUTDOWN - EXITING")
      Process.exit! 0
    end

    def stop_queue(name)
      worker = @queues[name]
      worker.status = "SHUTDOWN"
      Process.kill("TERM", worker.pid) rescue nil
    end

    def start_queue(name)
      worker = RQ::Queue.start_process({'name' => name})
      if worker
        @queues[worker.name] = worker
        $log.info("STARTED [ #{worker.name} - #{worker.pid} ]")
      end
    end

    def start_webserver
      @web_server = fork do
        # Restore default signal handlers from those inherited from queuemgr
        Signal.trap('TERM', 'DEFAULT')
        Signal.trap('CHLD', 'DEFAULT')

        $0 = $log.progname = '[rq-web]'
        Rack::Handler::UnixRack.run(
          RQ::Main.to_app(@config), {
          :Port        => @config['port'],
          :Host        => @config['addr'],
          :Hostname    => @config['host'],
          :allowed_ips => @config['allowed_ips'],
        })
      end
    end

    def load_queues
      # Skip dot dirs and queues already running
      queue_dirs.each do |name|
        next if @queues.has_key?(name)
        start_queue name
      end
    end

    def run!
      $0 = $log.progname = '[rq-mgr]'

      init
      load_config

      @signal_hup_rd, @signal_hup_wr = IO.pipe
      @signal_chld_rd, @signal_chld_wr = IO.pipe

      Signal.trap("TERM") do
        shutdown!
      end

      Signal.trap("CHLD") do
        @signal_chld_wr.syswrite('.')
      end

      Signal.trap("HUP") do
        @signal_hup_wr.syswrite('.')
      end

      load_queues

      start_webserver

      set_nonblocking(@sock)

      while true
        io_list = @queues.values.select { |i| i.status != "ERROR" }.map { |i| i.child_write_pipe }
        io_list << @sock
        io_list << @signal_hup_rd
        io_list << @signal_chld_rd
        begin
          ready, _, _ = IO.select(io_list, nil, nil, 60)
        rescue SystemCallError, StandardError # SystemCallError is the parent for all Errno::EFOO exceptions
          sleep 0.001 # A tiny pause to prevent consuming all CPU
          $log.warn("error on SELECT #{$!}")
          closed_sockets = io_list.delete_if { |i| i.closed? }
          $log.warn("removing closed sockets #{closed_sockets.inspect} from io_list")
          retry
        end

        next unless ready

        ready.each do |io|
          case io.fileno
          when @sock.fileno
            begin
              client_socket, client_sockaddr = @sock.accept
            rescue Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::ECONNABORTED, Errno::EPROTO, Errno::EINTR
              $log.warn('error acception on main sock, supposed to be readysleeping')
            end
            reset_nonblocking(client_socket)
            handle_request(client_socket)
            client_socket.close

          when @signal_hup_rd.fileno
            $log.debug("noticed SIGNAL HUP")
            reset_nonblocking(@signal_hup_rd)
            do_read(@signal_hup_rd, 1)
            reload

          when @signal_chld_rd.fileno
            $log.debug("noticed SIGNAL CHLD")
            reset_nonblocking(@signal_chld_rd)
            do_read(@signal_chld_rd, 1)

            # A child exited, figure out which one
            pid, status = Process.wait2(-1, Process::WNOHANG) rescue nil
            if pid
              worker = @queues.values.find { |o| o.pid == pid }
              handle_worker_close(worker, status) if worker
            end

          else
            # probably a child pipe that closed
            worker = @queues.values.find do |i|
              if i.child_write_pipe
                i.child_write_pipe.fileno == io.fileno
              end
            end
            pid, status = Process.wait2(worker.pid, Process::WNOHANG)
            handle_worker_close(worker, status) if worker
          end
        end

      end
    end

    def handle_worker_close(worker, status)
      $log.info("QUEUE PROC #{worker.name} of PID #{worker.pid} exited with status #{status} - #{worker.status}")
      worker.child_write_pipe.close

      case worker.status
      when 'RUNNING'
        if (@queue_errs[worker.name] += 1) > 10
          $log.warn("FAILED [ #{worker.name} - too many restarts. Not restarting ]")
          new_worker = RQ::Worker.new
          new_worker.status = 'ERROR'
          new_worker.name = worker.name
          @queues[worker.name] = new_worker
        else
          worker = RQ::Queue.start_process(worker.options)
          $log.info("RESTARTED [ #{worker.name} - #{worker.pid} ]")
          @queues[worker.name] = worker
        end

      when 'DELETE'
        RQ::Queue.delete(worker.name)
        @queues.delete(worker.name)
        $log.info("DELETED [ #{worker.name} ]")

      when 'SHUTDOWN'
        @queues.delete(worker.name)
        if @queues.empty?
          final_shutdown!
        end

      else
        $log.warn("STRANGE: queue #{worker.pid} status = #{worker.status}")
      end
    end

  end
end
