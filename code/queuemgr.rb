
require 'socket'
require 'json'

require 'code/queue'
require 'code/queueclient'

module RQ

  class Worker < Struct.new(:qc, :status, :child_write_pipe, :name,
                            :pid, :num_restarts, :options)
  end

  class QueueMgr

    attr_accessor :queues
    attr_accessor :status

    def initialize
      @queues = []
      @start_time = Time.now
      @status = "RUNNING"
      # Read config
    end

    def handle_request(sock)
      data = sock.recvfrom(1024)
      File.open('config/queuemgr.log', "a") do
        |f|
        f.write("#{Process.pid} - #{Time.now} - REQ [ #{data[0]} ]\n")
      end
      if data[0].index('ping') == 0
        sock.send("pong", 0)
        sock.close
        File.open('config/queuemgr.log', "a") do
          |f|
          f.write("#{Process.pid} - #{Time.now} - RESP [ pong ]\n")
        end
        return
      end
      if data[0].index('environment') == 0
        sock.send(ENV['RQ_ENV'], 0)
        sock.close
        File.open('config/queuemgr.log', "a") do
          |f|
          f.write("#{Process.pid} - #{Time.now} - RESP [ environment - #{ENV['RQ_ENV']} ]\n")
        end
        return
      end
      if data[0].index('queues') == 0
        data = @queues.map { |q| q.name }.to_json
        File.open('config/queuemgr.log', "a") do
          |f|
          f.write("#{Process.pid} - #{Time.now} - RESP [ #{data} ]\n")
        end
        sock.send(data, 0)
        sock.close
        return
      end

      if data[0].index('uptime') == 0
        data = [(Time.now - @start_time).to_i, ].to_json #['local','brserv_push'].to_json
        File.open('config/queuemgr.log', "a") do
          |f|
          f.write("#{Process.pid} - #{Time.now} - RESP [ #{data} ]\n")
        end
        sock.send(data, 0)
        sock.close
        return
      end

      if data[0].index('create_queue') == 0
        json = data[0].split(' ', 2)[1]
        options = JSON.parse(json)
        # "queue"=>{"name"=>"local", "script"=>"local.rb", "ordering"=>"ordered", "fsync"=>"fsync", "num_workers"=>"1", "url"=>"http://localhost:3333/"}} 
        if @queues.any? { |q| q.name == options['name'] }
          resp = ['fail', 'already created'].to_json
        else
          resp = ['fail', 'queue not created'].to_json
          results = RQ::Queue.create(options)
          File.open('config/queuemgr.log', "a") do
            |f|
            f.write("#{Process.pid} - #{Time.now} - STARTED [ #{options['name']}#{results[0]} ]\n")
          end
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
        File.open('config/queuemgr.log', "a") do
          |f|
          f.write("#{Process.pid} - #{Time.now} - RESP [ #{data} ]\n")
        end
        sock.send(resp, 0)
        sock.close
        return
      end

      sock.send("ERROR", 0)
      sock.close
      File.open('config/queuemgr.log', "a") do
        |f|
        f.write("#{Process.pid} - #{Time.now} - RESP [ ERROR ] - Unhandled message\n")
      end
    end

    def shutdown
      final_shutdown! if @queues.empty?
      
      @queues.each do
        |q|
        q.status = "SHUTDOWN"
      end

      @queues.each do
        |q|
        Process.kill("TERM", q.pid)
      end
    end

    def final_shutdown!
      # The actual shutdown happens when all procs are reaped
      File.unlink('config/queuemgr.pid') rescue nil
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

    def load_queues
      queues = Dir.entries('queue').reject {|i| i.include? '.'}
      
      queues.each do
        |q|
        start_queue q
      end
    end

  end
end

# TODO: Move these codez

def load_env_config
  ENV["RQ_ENV"] = "development"
  begin
    data = File.read('config/queuemgr.env')
    env = data.split('\n', 2)[0].strip
    ENV["RQ_ENV"] = env
  rescue
  end
end

def init
  # Show pid
  File.unlink('config/queuemgr.pid') rescue nil
  File.open('config/queuemgr.pid', "w") do
    |f|
    f.write("#{Process.pid}\n")
  end

  # Setup IPC
  File.unlink('config/queuemgr.sock') rescue nil
  $sock = UNIXServer.open('config/queuemgr.sock')

  load_env_config
end

def log(mesg)
  File.open('config/queuemgr.log', "a") do
    |f|
    f.write("#{Process.pid} - #{Time.now} - #{mesg}\n")
  end
end

def run_loop

  qmgr = RQ::QueueMgr.new

  Signal.trap("TERM") do
    log("received TERM signal")
    qmgr.shutdown
  end


  qmgr.load_queues

  require 'fcntl'
  flag = File::NONBLOCK
  if defined?(Fcntl::F_GETFL)
    flag |= $sock.fcntl(Fcntl::F_GETFL)
  end
  $sock.fcntl(Fcntl::F_SETFL, flag)


  # Ye old event loop
  while true
    io_list = qmgr.queues.map { |i| i.child_write_pipe }
    io_list << $sock
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
        worker = qmgr.queues.find { |i| i.child_write_pipe.fileno == io.fileno }
        if worker
          res = Process.wait2(worker.pid, Process::WNOHANG)
          if res
            log("QUEUE PROC #{worker.name} of PID #{worker.pid} exited with status #{res[1]}")
            worker.child_write_pipe.close
            if worker.status == "RUNNING"
              results = RQ::Queue.start_process(worker.options)
              log("STARTED [ #{worker.options['name']} - #{results[0]} ]")
              worker.pid = results[0]
              worker.child_write_pipe = results[1]
              worker.num_restarts += 1
            else
              qmgr.queues.delete(worker)
              if qmgr.queues.empty?
                qmgr.final_shutdown!
              end
            end
          else
            log("EXITING: queue #{worker.pid } was not ready to be reaped")
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

init
run_loop
