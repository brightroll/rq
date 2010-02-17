
require 'socket'
require 'json'
require 'fcntl'
require 'digest'

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

      @completed = [] # Messages that have properly set their status and exited properly

      @wait_time = 1

      if load_config() == false
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
      FileUtils.mkdir_p(queue_path + '/relayed')
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

    def run_queue_script!(msg)
      msg_id = msg['msg_id']

      basename = @queue_path + "/run/" + msg_id
      job_path = File.expand_path(basename + '/job/')
      Dir.mkdir(job_path) unless File.exists?(job_path)

      # TODO: Identify executable to run, if there is no script, go administratively down
      script_path = File.expand_path(@config['opts']['script'])
      if (not File.exists?(script_path)) && (not File.executable?(script_path))
        # Set queue adminitratively down
        log("queue down - script not there or runnable #{script_path}")
        @config['oper_status'] = 'DOWN'
        write_config
        return
      end

      log("0 child process prep step for runnable #{script_path}")
      # 0 = stdin, 1 = stdout, 2 = stderr, 4 = pipe
      #
      parent_rd, child_wr = IO.pipe

      log("1 child process prep step for runnable #{script_path}")
      log("1 child process prep step for runnable #{job_path}")

      child_pid = fork do
        # Setup env
        $0 = "[rq] [#{@name}] [#{msg_id}]"
        begin
          Dir.chdir(job_path)   # Chdir to child path

          RQ::Queue.log(job_path, "child process prep step for runnable #{script_path}")
          parent_rd.close
          #child only code block
          RQ::Queue.log(job_path, "post fork - child pipe fd: #{child_wr.fileno}")

          # Unix house keeping
          #self.close_all_fds([child_wr.fileno])

          if child_wr.fileno != 3
            IO.for_fd(3).close rescue nil
            fd = child_wr.fcntl(Fcntl::F_DUPFD, 3)
            RQ::Queue.log(job_path, "Error duping fd for 3 - got #{fd}") unless fd == 3
            #... the pipe fd will get closed on exec
          end

          f = File.open(job_path + "/stdio.log", "a")
          RQ::Queue.log(job_path, "stdio.log has fd of #{f.fileno}")
          if f.fileno != 0
            IO.for_fd(0).close rescue nil
          end
          if f.fileno != 1
            IO.for_fd(1).close rescue nil
          end
          if f.fileno != 2
            IO.for_fd(2).close rescue nil
          end

          if f.fileno != 0
            fd = f.fcntl(Fcntl::F_DUPFD, 0)
            RQ::Queue.log(job_path, "Error duping fd for 0 - got #{fd}") unless fd == 0
          end
          if f.fileno != 1
            fd = f.fcntl(Fcntl::F_DUPFD, 1)
            RQ::Queue.log(job_path, "Error duping fd for 1 - got #{fd}") unless fd == 1
          end
          if f.fileno != 2
            fd = f.fcntl(Fcntl::F_DUPFD, 2)
            RQ::Queue.log(job_path, "Error duping fd for 2 - got #{fd}") unless fd == 2
          end

          RQ::Queue.log(job_path, 'post stdio re-assigning') unless fd == 2
          (4..1024).each do |io|
            io = IO.for_fd(io) rescue nil
            next unless io
            io.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
          end
          RQ::Queue.log(job_path, 'post FD_CLOEXEC') unless fd == 2

          RQ::Queue.log(job_path, "running #{script_path}")

          ENV["RQ_HOST"] = @config['opts']['url']
          ENV["RQ_DEST"] = gen_full_dest(msg)['dest']
          ENV["RQ_DEST_QUEUE"] = gen_full_dest(msg)['queue']
          ENV["RQ_MSG_ID"] = msg_id
          ENV["RQ_MSG_DIR"] = job_path
          ENV["RQ_PIPE"] = "3"
          ENV["RQ_COUNT"] = msg.fetch('count', 0).to_s
          ENV["RQ_PARAM1"] = msg['param1']
          ENV["RQ_PARAM2"] = msg['param2']
          ENV["RQ_PARAM3"] = msg['param3']
          ENV["RQ_PARAM4"] = msg['param4']

          # unset RUBYOPT so it doesn't reinitialize the client ruby's GEM_HOME, etc.
          ENV.delete("RUBYOPT")

#          RQ::Queue.log(job_path, "set ENV now executing #{msg.inspect}")

          RQ::Queue.log(job_path, "set ENV, now executing #{script_path}")

          # bash -lc will execute the command but first re-initializing like a new login (reading .bashrc, etc.)
          exec("bash -lc #{script_path}")
        rescue
          RQ::Queue.log(job_path, $!)
          RQ::Queue.log(job_path, $!.backtrace)
          raise
        end
      end

      #parent only code block
      child_wr.close

      if child_pid == nil
        parent_rd.close
        log("failed to run child script: queue_path, $!")
        return nil
      end

      msg['child_pid'] = child_pid
      msg['child_read_pipe'] = parent_rd
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

    def check_msg(msg, input)
      # Required parameter
      return false unless input.has_key?('dest')
      msg['dest'] = input['dest']

      # Copy only these keys from input message
      keys = %w(src count param1 param2 param3 param3)
      keys.each do
        |key|
        next unless input.has_key?(key)
        msg[key] = input[key]
      end

      return true
    end

    def store_msg(msg, que = 'prep')
      # Write message to disk
      begin
        if not msg.has_key?('due')
          msg['due'] = Time.now.to_i
        end
        clean = msg.reject { |k,v| k == 'child_read_pipe' }
        data = clean.to_json
        # Need a sysopen style system here TODO
        basename = @queue_path + "/#{que}/" + msg['msg_id']
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
        # Read in full message
        msg = get_message(msg, from_state)
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

      run_scheduler!

      return true
    end

    def run_job(msg, from_state = 'que')
      msg_id = msg['msg_id']
      begin
        basename = @queue_path + "/#{from_state}/" + msg_id
        return false unless File.exists? basename
        newname = @queue_path + "/run/" + msg_id
        File.rename(basename, newname)
      rescue
        log("FATAL - couldn't run message #{msg_id}")
        log("        [ #{$!} ]")
        return false
      end

      # Put in run queue
      @que.delete(msg)
      @run.unshift(msg)

      run_queue_script!(msg)

      return true
    end

    def lookup_msg(msg, state = 'prep')
      msg_id = msg['msg_id']
      if state == 'prep'
        basename = @queue_path + "/#{state}/" + msg_id
        if @prep.include?(msg_id) == false
          return false
        end
      end
      if state == '*'
        while true
          if @prep.include?(msg_id)
            state = 'prep'
            break
          end
          if @que.find { |o| o['msg_id'] == msg_id }
            state = 'que'
            break
          end
          if @run.find { |o| o['msg_id'] == msg_id }
            state = 'run'
            break
          end
          if not Dir.glob("#{@queue_path}/done/#{msg_id}").empty?
            state = 'done'
            break
          end
          if not Dir.glob("#{@queue_path}/relayed/#{msg_id}").empty?
            state = 'relayed'
            break
          end
          if not Dir.glob("#{@queue_path}/err/#{msg_id}").empty?
            state = 'err'
            break
          end
          if not Dir.glob("#{@queue_path}/pause/#{msg_id}").empty?
            state = 'pause'
            break
          end

          break
        end

        return false unless state != '*'
        basename = @queue_path + "/#{state}/" + msg_id
      end
      if not File.exists?(basename)
        log("WARNING - serious queue inconsistency #{msg_id}")
        log("WARNING - #{msg_id} in memory but not on disk")
        return false
      end
      return state
    end

    def delete_msg!(msg)
      state = lookup_msg(msg, '*')
      return nil unless state

      basename = @queue_path + "/#{state}/" + msg['msg_id']

      if state == 'prep'
        #FileUtils.remove_entry_secure(basename)
        FileUtils.rm_rf(basename)
        @prep.delete(msg['msg_id'])
      end
      if state == 'que'
        #FileUtils.remove_entry_secure(basename)
        FileUtils.rm_rf(basename)
        @que.delete_if { |o| o['msg_id'] == msg['msg_id'] }
      end
      # TODO
      # run
      # pause
      # done
    end

    def get_message(params, state)
      basename = @queue_path + "/#{state}/" + params['msg_id']

      msg = nil
      begin
        data = File.read(basename + "/msg")
        msg = JSON.parse(data)
        msg['status'] = state
        if File.exists?(basename + "/status")
          xtra_data = File.read(basename + "/status")
          xtra_status = JSON.parse(xtra_data)
          msg['status'] += " - #{xtra_status['job_status']}"
        end

        # Now check for attachments
        if File.directory?(basename + "/attach/")
          ents = Dir.entries(basename + "/attach/").reject {|i| i.index('.') == 0 }
          if not ents.empty?
            msg['_attachments'] = { }
            ents.each do
              |ent|
              msg['_attachments'][ent] = { }
              md5, size = file_md5("#{basename}/attach/#{ent}")
              msg['_attachments'][ent]['md5'] = md5
              msg['_attachments'][ent]['size'] = size
            end
          end
        end

      rescue
        msg = nil
        log("Bad message in queue: #{basename}")
        log("        [ #{$!} ]")
      end

      return msg
    end

    def gen_full_msg_id(msg)
      full_name = "#{@config['opts']['url']}q/#{@name}/#{msg['msg_id']}"
      return full_name
    end

    def gen_full_dest(msg)
      res = { 'dest' => "#{@config['opts']['url']}q/#{msg['dest']}/",
        'queue' => msg['dest'] }

      # IF message already has full remote dest...
      if msg['dest'].index('http:') == 0
        res['dest'] = msg['dest']
        q_name = msg['dest'][/\/q\/([^\/]+)/, 1]
        res['queue'] = q_name;
        #msg_id = msg['dest'][/\/q\/[^\/]+\/([^\/]+)/, 1]
      end

      res
    end

    def attach_msg(msg)
      msg_id = msg['msg_id']
      # validate attachment
      result = [false, 'Unknown error']
      begin
        basename = @queue_path + "/prep/" + msg_id
        return [false, "No message on disk"] unless File.exists? basename

        #TODO: deal with symlinks
        # simple early check, ok, now check for pathname
        return [false, "Invalid pathname, must be normalized #{msg['pathname']} (ie. must start with /"] unless msg['pathname'].index("/") == 0
        return [false, "No such file #{msg['pathname']} to attach to message"] unless File.exists?(msg['pathname'])
        return [false, "Attachment currently cannot be a directory #{msg['pathname']}"] if File.directory?(msg['pathname'])
        return [false, "Attachment currently cannot be read: #{msg['pathname']}"] unless File.readable?(msg['pathname'])
        return [false, "Attachment currently not of supported type: #{msg['pathname']}"] unless File.file?(msg['pathname'])


        # simple check for attachment dir
        attach_path = basename + '/attach/'
        Dir.mkdir(attach_path) unless File.exists?(attach_path)

        # OK do we have a name?
        # Try that first, else use basename
        name = msg['name'] || File.basename(msg['pathname'])

        # Validate - that it does not have any '/' chars or a '.' prefix
        if (name.index(".") == 0)
          return [false, "Attachment name as a dot-file not allowed: #{name}"]
        end
        # Unsafe char removal
        name_test = name.tr('~?[]|$&<>', '*')
        if name_test.index("*")
          return [false, "Attachment name has invalid chara dot-file not allowed: #{name}"]
        end
        #  TODO: support directory moves

        # OK is path on same filesystem?
        # stat of basename
        if File.stat(attach_path).dev != File.stat(msg['pathname']).dev
          return [false, "Attachment must be on same filesystem as que: #{msg['pathname']}"]
        end

        # No  - is local_fs_only set, then error out
        #       FOR NOW: error out (tough Shit!), blocking would take too long MF
        #       TODO: else, make a copy in
        #             ELSE, lock, fork, do copy, return status updates, complex yada yada
        #       SCREW THIS: let the client do the prep on the cmd line
        # Yes - good - just do a link, then rename

        #       First hardlink to temp file that doesn't exist (link will fail
        #       if new name already exists in dir
        new_path = attach_path + name
        tmp_new_path = attach_path + name + '.tmp'
        File.unlink(tmp_new_path) rescue nil
        File.link(msg['pathname'], tmp_new_path)
        #       Second, do a rename, that will overwrite

        md5, size = file_md5(tmp_new_path)

        File.rename(tmp_new_path, new_path)
        # DONE

        result = [true, "#{md5}-Attached successfully"]
      rescue
        log("FATAL - couldn't add attachment to message #{msg_id}")
        log("        [ #{$!} ]")
        return false
      end

      return result
    end

    def file_md5(path)
      hasher = Digest::MD5.new

      size = nil
      File.open(path, 'r') do |file|
        size = file.stat.size
        hasher.update(file.read(32768)) until file.eof
      end

      result = hasher.hexdigest
      [result, size]
    end

    def fixup_msg(msg, que)
      needs_fixing = false
      if not msg.has_key?('due')
        needs_fixing = true
      end

      if needs_fixing
        store_msg(msg, que)
      end
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
          fixup_msg(msg, 'que')
        rescue
          log("Bad message in queue: #{mname}")
          next
        end
        @que << msg
      end

      # run has actual messages copied
      basename = @queue_path + '/run/'
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
        @run << msg
      end
    end

    def handle_status_read(msg)
      msg_id = msg['msg_id']
      child_io = msg['child_read_pipe']

      log("Reading status from child")
      # I should just use sysread and syswrite everywhere
      # the ruby IO model removes power from those who know
      # with wrappers written by those who do not know
      # update... using sysread
      data = ""
      loop do
        begin
          #child_io.sysread(4096)
          #data += child_io.readpartial(4096)
          data += child_io.sysread(4096)
          break
        rescue Errno::EAGAIN, Errno::EINTR
          #log("Error: #{$!}")
          retry
        rescue EOFError
          #log("EOFError - #{$!}")
          break
        end
      end

      #if data
      #  log("Done Reading status from child len: #{data.length}")
      #else
      #  log("Done Reading status from child (nil)")
      #end

      return false if data.empty?

      child_msgs = data.split("\n")

      child_msgs.each do
        |child_msg|
        parts = child_msg.split(" ", 2)

        # Always write message status
        write_msg_status(msg, parts[1])

        # BELOW - changed my mind about moving the message into its new
        # queue. Why? What if the msg says it is done, but the process
        # doesn't exit cleanly. That would be bad form. The safe thing
        # to do is to re-run the process if there is a crash (for now)

        # Also, we record the timestamp of this message in the completion
        # This allows us to notice any processes that have failed to terminate
        # and then kill them down the road.

        if (parts[0] != "run")
          log("Non 'run' status came in: #{parts[0]}")
          if parts[0] == 'done'
            @completed << [msg, :done, Time.now.to_i]
          end
          if parts[0] == 'fail' || parts[0] == 'err'
            @completed << [msg, :err, Time.now.to_i]
            ## THE QUESTIONS: Do we kill the job now?
            # No  - up to script writer. They should exit
            #       we'll trust them for now
          end
          if parts[0] == 'pause'
            @completed << [msg, :pause, Time.now.to_i]
          end
          if parts[0] == 'relayed'
            @completed << [msg, :relayed, Time.now.to_i]
          end
          if parts[0] == 'resend'
            @completed << [msg, :resend, parts[1].to_i]
            due,reason = parts[1].split('-')
            msg['due'] = Time.now.to_i + due.to_i
            msg['count'] = msg.fetch('count', 0) + 1
            store_msg(msg, 'run')
            # *** THIS ONE IS DIFFERENT ***
            # We need to set the messages 'due' time. This is safe
            # since we are in the run queue, and we want to record
            # this to disk before moving on 
          end
        end
      end

      return true
    end

    def write_msg_status(msg, mesg)
      # Write message to disk
      begin
        data = { 'job_status' => mesg }.to_json
        basename = @queue_path + "/run/" + msg['msg_id'] + "/status"
        File.open(basename + '.tmp', 'w') { |f| f.write(data) }
        File.rename(basename + '.tmp', basename)
      rescue
        log("FATAL - couldn't write status message")
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

    def run_scheduler!
      @wait_time = 60

      # If oper_status != "UP"
      if (@config['admin_status'] != "UP") && (@config['oper_status'] != "UP")
        log("Status != up  admin: #{@config['admin_status']}  oper: #{@config['oper_status']}")
        return
      end

      # Are we arleady running max workers
      active_count = @run.inject(0) do
        |acc,o|
        if o.has_key?('child_pid')
          acc = acc + 1
        end
        acc
      end

      if active_count >= @config['opts']['num_workers'].to_i
        #log("Already running #{active_count} config is max: #{@config['opts']['num_workers']}")
        return
      end

      # If we got started, and there are jobs in run que, but
      # without any workers
      if @run.length != active_count
        job = @run.find { |o| not o.has_key?('child_pid') }
        run_queue_script!(job)
        return
      end

      if @que.empty?
        return
      end

      # Ok, locate the next job
      sorted = @que.sort_by { |e| e['due'] }

      delta = sorted[0]['due'].to_i - Time.now.to_i

      # If it is time to wait, then run 
      if delta >= 0
        if delta < 60  # Set timeout to be this, vs default of 60 set above
          @wait_time = delta
        end
        return
      end

      # Looks like it is time to run now...
      run_job(sorted[0])
      run_scheduler!   # Tail recursion, fail me now, I'm in Ruby
                       # So, lets hope the load isn't too high
                       # If it is, then we will loop like crazy
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
        run_scheduler!

        io_list = @run.map { |i| i['child_read_pipe'] }
        io_list.compact!
        io_list << @sock
        io_list << @parent_pipe
        #log('sleeping') if @wait_time == 60
        begin
          ready = IO.select(io_list, nil, nil, @wait_time)
        rescue Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::ECONNABORTED, Errno::EPROTO, Errno::EINTR
          log("error on SELECT #{$!}")
          retry
        end

        # TODO: handle children that have reported a state change, but have
        #       not exited

        # If no timeout occurred
        if ready
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
              next
            elsif io.fileno == @parent_pipe
              log("QUEUE #{@name} of PID #{Process.pid} noticed parent close exiting...")
              shutdown!
              next
            end

            msg = @run.find { |o| o['child_read_pipe'].fileno == io.fileno }
            if msg
              #log("QUEUE #{@name} of PID #{Process.pid} noticed child pipe readable... #{msg['child_pid']}")
              #log("QUEUE #{@name} of PID #{Process.pid} #{msg['child_read_pipe'].object_id} <=> #{io.object_id}")

              # TODO: make this stateful for incomplete reads
              next if handle_status_read(msg)

              log("QUEUE #{@name} of PID #{Process.pid} noticed child pipe close... #{msg['child_pid']}")

              res = Process.wait2(msg['child_pid'], Process::WNOHANG)
              if res
                log("QUEUE PROC #{@name} PID #{Process.pid} noticed child #{msg['child_pid']} exit with status #{res.inspect}")

                msg_id = msg['msg_id']

                # Ok, close the pipe on our end
                msg['child_read_pipe'].close
                msg.delete('child_read_pipe')

                # Determine status of msg
                completion = @completed.find { |i| i[0]['msg_id'] == msg_id }

                if completion
                  log("QUEUE PROC #{@name} PID #{Process.pid} child #{msg['child_pid']} completion [#{completion.inspect}]")
                else
                  log("QUEUE PROC #{@name} PID #{Process.pid} child #{msg['child_pid']} NO COMPLETION")
                  completion = [nil, nil, nil]
                end

                new_state = nil
                if completion[1] == :done && res[1] == 0
                  new_state = 'done'
                end

                if completion[1] == :relayed && res[1] == 0
                  new_state = 'relayed'
                end

                if completion[1] == :err
                  new_state = 'err'
                end

                #if completion[1] == :pause
                #  new_state = 'err'
                #end

                if completion[1] == :resend && res[1] == 0
                  new_state = 'que'
                end

                if new_state == nil
                  # log a message
                  write_msg_status(msg, "PROCESS EXITED IMPROPERLY - MOVING TO ERR- Expected #{completion[1]} - and - status #{res.inspect}" )
                  write_msg_status(msg, "PROCESS EXITED IMPROPERLY" )
                  new_state = 'err'
                end

                # Move to relay dir and update in-memory data structure
                begin
                  basename = "#{@queue_path}/run/#{msg_id}"
                  raise unless File.exists? basename
                  newname = "#{@queue_path}/#{new_state}/#{msg_id}"
                  File.rename(basename, newname)
                rescue
                  log("FATAL - couldn't move from 'run' to 'relay' #{msg_id}")
                  log("        [ #{$!} ]")
                  next
                end

                log("Prior to resend: run - #{@run.length} que - #{@que.length} completed - #{@completed.length}")
                # Remove from completion
                @completed.delete(completion)
                # Remove from run
                @run = @run.reject { |i| i['msg_id'] == msg_id }

                if (completion[1] == :resend) && (new_state == 'que')
                  # Re-inject into que
                  msg['due'] = Time.now.to_i + completion[2]
                  @que.unshift(msg)

                  log("Did resend: run - #{@run.length} que - #{@que.length} completed - #{@completed.length}")

                  # No-need to re-run scheduler, it runs on every iteration
                  # of this loop
                end

              else
                log("EXITING: queue #{@name} - script msg #{msg['child_pid']} was not ready to be reaped")
              end

            else
              log("QUEUE #{@name} of PID #{Process.pid} noticed fd close on fd #{io.fileno}...")

            end
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
        if alloc_id(msg) and check_msg(msg, options)
          store_msg(msg)
          que(msg)
          msg_id = gen_full_msg_id(msg)
          resp = [ "ok", msg_id ].to_json
        else
          resp = [ "fail", "unknown reason"].to_json
        end
        log("RESP [ #{resp} ]")
        sock.send(resp, 0)
        sock.close
        return
      end

      if data[0].index('single_que') == 0
        json = data[0].split(' ', 2)[1]
        options = JSON.parse(json)

        msg = { }

        if not @que.empty?
          msg_id = gen_full_msg_id(@que[0])
          resp = [ "ok", msg_id ].to_json
        elsif alloc_id(msg) and check_msg(msg, options)
          store_msg(msg)
          que(msg)
          msg_id = gen_full_msg_id(msg)
          resp = [ "ok", msg_id ].to_json
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
        status['que']    = @que.map { |m| [m['msg_id'], m['due']] }
        status['run']    = @run.map { |m| [m['msg_id'], m['status']] }
        status['pause']  = []
        status['done']   = Dir.entries(@queue_path + "/done/").reject {|i| i.index('.') == 0 }
        status['relayed']  = Dir.entries(@queue_path + "/relayed/").reject {|i| i.index('.') == 0 }
        status['err']  = Dir.entries(@queue_path + "/err/").reject {|i| i.index('.') == 0 }

        resp = status.to_json
        log("RESP [ #{resp} ]")
        sock.send(resp, 0)
        sock.close
        return
      end

      if data[0].index('prep_message') == 0
        json = data[0].split(' ', 2)[1]
        options = JSON.parse(json)

        msg = { }
        if alloc_id(msg) and check_msg(msg, options)
          store_msg(msg)
          msg_id = gen_full_msg_id(msg)
          resp = [ "ok", msg_id ].to_json
        else
          resp = [ "fail", "unknown reason"].to_json
        end
        log("RESP [ #{resp} ]")
        sock.send(resp, 0)
        sock.close
        return
      end

      if data[0].index('attach_message') == 0
        json = data[0].split(' ', 2)[1]
        options = JSON.parse(json)

        if not options.has_key?('msg_id')
          resp = [ "fail", "lacking 'msg_id' field"].to_json
          log("RESP [ #{resp} ]")
          sock.send(resp, 0)
          sock.close
          return
        end

        if lookup_msg(options)
          success, attach_message = attach_msg(options)
          if success
            resp = [ "ok", attach_message ].to_json
          else
            resp = [ "fail", attach_message ].to_json
          end
        else
          resp = [ "fail", "couldn't locate message in prep"].to_json
        end
        log("RESP [ #{resp} ]")
        sock.send(resp, 0)
        sock.close
        return
      end

      if data[0].index('commit_message') == 0
        json = data[0].split(' ', 2)[1]
        options = JSON.parse(json)

        if not options.has_key?('msg_id')
          resp = [ "fail", "lacking 'msg_id' field"].to_json
          log("RESP [ #{resp} ]")
          sock.send(resp, 0)
          sock.close
          return
        end

        resp = [ "fail", "unknown reason"].to_json

        if lookup_msg(options) and que(options)
          resp = [ "ok", "msg commited" ].to_json
        end

        log("RESP [ #{resp} ]")
        sock.send(resp, 0)
        sock.close
        return
      end

      if data[0].index('get_message') == 0
        json = data[0].split(' ', 2)[1]
        options = JSON.parse(json)

        if not options.has_key?('msg_id')
          resp = [ "fail", "lacking 'msg_id' field"].to_json
          log("RESP [ #{resp} ]")
          sock.send(resp, 0)
          sock.close
          return
        end

        resp = [ "fail", "unknown reason"].to_json

        state = lookup_msg(options, '*')
        if state
          msg = get_message(options, state)
          if msg
            resp = [ "ok", msg ].to_json
          else
            resp = [ "fail", "msg couldn't be read" ].to_json
          end
        else
          resp = [ "fail", "msg not found" ].to_json
        end

        log("RESP [ #{resp} ]")
        sock.send(resp, 0)
        sock.close
        return
      end

      if data[0].index('delete_message') == 0
        json = data[0].split(' ', 2)[1]
        options = JSON.parse(json)

        if not options.has_key?('msg_id')
          resp = [ "fail", "lacking 'msg_id' field"].to_json
          log("RESP [ #{resp} ]")
          sock.send(resp, 0)
          sock.close
          return
        end

        resp = [ "fail", "unknown reason"].to_json

        if lookup_msg(options, '*')
          delete_msg!(options)
          resp = [ "ok", "msg commited" ].to_json
        else
          resp = [ "fail", "msg not found" ].to_json
        end

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


