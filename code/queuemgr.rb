
require 'socket'
require 'json'

require 'code/queue'
require 'code/queueclient'
require 'code/scheduler'
require 'version'

def log(mesg)
  File.open('log/queuemgr.log', "a") do
    |f|
    f.write("#{Process.pid} - #{Time.now} - #{mesg}\n")
  end
end

module RQ

  class Worker < Struct.new(:qc, :status, :child_write_pipe, :name,
                            :pid, :num_restarts, :options)
  end

  class QueueMgr

    attr_accessor :queues
    attr_accessor :scheduler
    attr_accessor :status
    attr_accessor :host
    attr_accessor :port
    attr_accessor :environment

    def initialize
      @queues = []
      @scheduler = nil
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

      load_config
    end

    def handle_request(sock)
      data = sock.recvfrom(1024)
      log("REQ [ #{data[0]} ]");
      if data[0].index('ping') == 0
        sock.send("pong", 0)
        sock.close
        log("RESP [ pong ]");
        return
      end
      if data[0].index('environment') == 0
        sock.send(ENV['RQ_ENV'], 0)
        sock.close
        log("RESP [ environment - #{ENV['RQ_ENV']} ]")
        return
      end
      if data[0].index('version') == 0
        data = [ ENV['RQ_VER'], ENV['RQ_SEMVER'] ].to_json
        sock.send(data, 0)
        sock.close
        log("RESP [ version - #{data} ]")
        return
      end
      if data[0].index('queues') == 0
        data = @queues.map { |q| q.name }.to_json
        log("RESP [ queues - #{data} ]")
        sock.send(data, 0)
        sock.close
        return
      end

      if data[0].index('uptime') == 0
        data = [(Time.now - @start_time).to_i, ].to_json #['local','brserv_push'].to_json
        log("RESP [ uptime - #{data} ]")
        sock.send(data, 0)
        sock.close
        return
      end

      if data[0].index('restart_queue ') == 0
        queuename = data[0].split(' ', 2)[1]
        log("RESP [ restart_queue - #{queuename} ]")
        worker = @queues.find { |i| i.name == queuename }
        status = 'fail'
        if worker.status == "RUNNING"
          Process.kill("TERM", worker.pid) rescue nil
          status = 'ok'
        else
          # TODO
          # when I have timers, do this as a message to main event loop
          # to centralize this code
          results = RQ::Queue.start_process(worker.options)
          if results
            log("STARTED [ #{worker.options['name']} - #{results[0]} ]")
            worker.status = "RUNNING"
            worker.num_restarts = 0
            worker.pid = results[0]
            worker.child_write_pipe = results[1]
            status = 'ok'
          end
        end
        resp = [status, queuename].to_json #['ok','brserv_push'].to_json
        sock.send(resp, 0)
        sock.close
        return
      end

      if data[0].index('create_queue ') == 0
        json = data[0].split(' ', 2)[1]
        options = JSON.parse(json)
        # "queue"=>{"name"=>"local", "script"=>"local.rb", "ordering"=>"ordered", "fsync"=>"fsync", "num_workers"=>"1", }} 

        if @queues.any? { |q| q.name == options['name'] }
          resp = ['fail', 'already created'].to_json
        else
          # Validate characters in name
          # No '.' or '/' since that could change path
          # Basically it should just be alphanum and '-' or '_'
          name_test = options['name'].tr('/. ,;:@"(){}\\+=\'^`#~?[]%|$&<>', '*')
          if name_test.index("*")
            resp = ['fail', "queue name has invalid characters"].to_json
          else
            resp = ['fail', 'queue not created'].to_json
            results = RQ::Queue.create(options)
            log("create_queue STARTED [ #{options['name']}#{results[0]} ]")
            if results
              qc = QueueClient.new(options['name'])
              worker = Worker.new
              worker.name = options['name']
              worker.qc = qc
              worker.options = options
              worker.status = "RUNNING"
              worker.pid = results[0]
              worker.child_write_pipe = results[1]
              worker.num_restarts = 0
              @queues << worker
              resp = ['success', 'queue created - awesome'].to_json
            end
          end
        end
        log("RESP [ #{resp} ]")
        sock.send(resp, 0)
        sock.close
        return
      end

      if data[0].index('create_queue_link ') == 0
        json_path = data[0].split(' ', 2)[1]

        options = {}
        err = false

        # Validate path
        json_data = false
        begin
          json_data = File.read(json_path)
        rescue
          resp = ['fail', 'could not read json config'].to_json
          err = true
        end

        # Lightweight validate json

        if not err
          begin
            options = JSON.parse(json_data)
          rescue
            resp = ['fail', 'could not parse json config'].to_json
            err = true
          end
        end

        if not err
          if options.include?('name')
            if (1..128).include?(options['name'].size)
              if options['name'].class != String
                resp = ['fail', "json config has invalid name (not String)"].to_json
                err = true
              end
            else
              resp = ['fail', "json config has invalid name (size)"].to_json
              err = true
            end
          else
            resp = ['fail', 'json config is missing name field'].to_json
            err = true
          end
        end

        if not err
          if options.include?('num_workers')
            if not ( (1..128).include?(options['num_workers'].to_i) )
              resp = ['fail', "json config has invalid num_workers field (out of range 1..128)"].to_json
              err = true
            end
          else
            resp = ['fail', 'json config is missing num_workers field'].to_json
            err = true
          end
        end

        if not err
          if options.include?('script')
            if (1..1024).include?(options['script'].size)
              if options['script'].class != String
                resp = ['fail', "json config has invalid script (not String)"].to_json
                err = true
              end
            else
              resp = ['fail', "json config has invalid script (size)"].to_json
              err = true
            end
          else
            resp = ['fail', 'json config is missing script field'].to_json
            err = true
          end
        end

        if not err
          if @queues.any? { |q| q.name == options['name'] }
            resp = ['fail', 'already created'].to_json
            err = true
          end
        end

        if not err
          name_test = options['name'].tr('/. ,;:@"(){}\\+=\'^`#~?[]%|$&<>', '*')
          if name_test.index("*")
            resp = ['fail', "queue name has invalid characters"].to_json
            err = true
          end
        end

        if not err
          resp = ['fail', 'queue not created'].to_json
          results = RQ::Queue.create(options, json_path)
          log("create_queue STARTED [ #{options['name']}#{results[0]} ]")
          if results
            qc = QueueClient.new(options['name'])
            worker = Worker.new
            worker.name = options['name']
            worker.qc = qc
            worker.options = options
            worker.status = "RUNNING"
            worker.pid = results[0]
            worker.child_write_pipe = results[1]
            worker.num_restarts = 0
            @queues << worker
            resp = ['success', 'queue created - awesome'].to_json
          end
        end

        log("RESP [ #{resp} ]")
        sock.send(resp, 0)
        sock.close
        return
      end

      if data[0].index('delete_queue ') == 0
        queuename = data[0].split(' ', 2)[1]
        worker = @queues.find { |i| i.name == queuename }
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
        return
      end

      sock.send("ERROR", 0)
      sock.close
      log("RESP [ ERROR ] - Unhandled message")
    end

    def shutdown
      final_shutdown! if @queues.empty?
      
      # Remove non-running entries
      @queues = @queues.select { |q| q.pid }

      @queues.each do |q|
        q.status = "SHUTDOWN"
      end

      @queues.each do |q|
        Process.kill("TERM", q.pid) if q.pid
      end
    end

    def final_shutdown!
      # Once all the queues are down, take the scheduler down
      Process.kill("TERM", @scheduler.pid) if @scheduler.pid

      # The actual shutdown happens when all procs are reaped
      File.unlink('config/queuemgr.pid') rescue nil
      $sock.close
      File.unlink('config/queuemgr.sock') rescue nil
      log("FINAL SHUTDOWN - EXITING")
      Process.exit! 0
    end

    def start_queue(qname)
      options = { }
      options['name'] = qname
      results = RQ::Queue.start_process(options)
      if results
        qc = QueueClient.new(options['name'])
        worker = Worker.new
        worker.name = options['name']
        worker.qc = qc
        worker.options = options
        worker.status = "RUNNING"
        worker.pid = results[0]
        worker.child_write_pipe = results[1]
        worker.num_restarts = 0
        @queues << worker
        log("STARTED [ #{worker.options['name']} - #{results[0]} ]")
      end
    end

    def start_scheduler
      options = { }
      results = RQ::Scheduler.start_process(options)
      if results
        worker = Worker.new
        worker.name = "scheduler"
        worker.qc = nil
        worker.options = options
        worker.status = "RUNNING"
        worker.pid = results[0]
        worker.child_write_pipe = results[1]
        worker.num_restarts = 0
        @scheduler = worker
        log("STARTED [ scheduler ] - #{results[0]} ]")
      end
    end


    def load_queues
      queues = Dir.entries('queue').reject {|i| i.include? '.'}
      
      queues.each do |q|
        start_queue q
      end
    end

  end
end

# TODO: Move these codez

def run_loop

  qmgr = RQ::QueueMgr.new

  qmgr.init

  Signal.trap("TERM") do
    log("received TERM signal")
    qmgr.shutdown
  end

  Signal.trap("CHLD") do
    log("received CHLD signal")
  end

  qmgr.load_queues

  qmgr.start_scheduler

  require 'fcntl'
  flag = File::NONBLOCK
  if defined?(Fcntl::F_GETFL)
    flag |= $sock.fcntl(Fcntl::F_GETFL)
  end
  $sock.fcntl(Fcntl::F_SETFL, flag)


  # Ye old event loop
  while true
    #log(qmgr.queues.select { |i| i.status != "ERROR" }.map { |i| [i.name, i.child_write_pipe] }.inspect)
    io_list = qmgr.queues.select { |i| i.status != "ERROR" }.map { |i| i.child_write_pipe }
    io_list << $sock
    #log(io_list.inspect)
    log('sleeping')
    begin
      ready = IO.select(io_list, nil, nil, 60)
    rescue Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::ECONNABORTED, Errno::EPROTO, Errno::EINTR
      log("error on SELECT #{$!}")
      retry
    end

    next unless ready

    ready[0].each do |io|
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
        qmgr.handle_request(client_socket)
      else
        # probably a child pipe that closed
        worker = qmgr.queues.find {
          |i|
          if i.child_write_pipe
            i.child_write_pipe.fileno == io.fileno
          else
            false
          end
        }
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
              qmgr.queues.delete(worker)
              log("DELETED [ #{worker.name} ]")
            elsif worker.status == "SHUTDOWN"
              qmgr.queues.delete(worker)
              if qmgr.queues.empty?
                qmgr.final_shutdown!
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

#     begin
#       #client_socket, client_sockaddr = $sock.accept_nonblock
#       client_socket, client_sockaddr = $sock.accept
#     rescue Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::ECONNABORTED, Errno::EPROTO, Errno::EINTR
#       log('sleeping')
#       IO.select([$sock], nil, nil, 60)
#       retry
#     end

  end
end

run_loop
