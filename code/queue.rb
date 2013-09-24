require 'socket'
require 'json'
require 'fcntl'
require 'digest'
require 'fileutils'
require 'code/unixrack'
require 'code/hashdir'
require 'code/adminoper'
require 'code/queueclient'
require 'code/jsonconfigfile'
require 'pathname'

module RQ

  class Worker < Struct.new(
    :qc,
    :name,
    :status,
    :child_write_pipe,
    :pid,
    :num_restarts,
    :options
  )
  end

  class QueueConfig < Struct.new(
    :name,
    :script,
    :num_workers,
    :exec_prefix,
    :env_vars,
    :coalesce,
    :coalesce_params
  )
  end

  class Queue

    def initialize(options, parent_pipe)
      @start_time = Time.now
      # Read config
      @name = options['name']
      @queue_path = "queue/#{@name}"
      @rq_config_path = "./config/"
      @parent_pipe = parent_pipe
      init_socket

      @prep   = []  # should be small
      @que    = []  # could be large
      @run    = []  # should be small

      @completed = [] # Messages that have properly set their status and exited properly

      @wait_time = 1

      @status = RQ::AdminOper.new(@rq_config_path + @name)

      @temp_que_dups = {}

      @signal_hup_rd, @signal_hup_wr = IO.pipe

      Signal.trap("TERM") do
        log("received TERM signal")
        shutdown!
      end

      Signal.trap("HUP") do
        # Ye Ole DJB self_pipe trick again
        @signal_hup_wr.syswrite('.')
      end

      unless load_rq_config
        sleep 5
        log("Invalid main rq config for #{@name}. Exiting." )
        exit! 1
      end

      unless load_config
        sleep 5
        log("Invalid config for #{@name}. Exiting." )
        exit! 1
      end

      load_messages

      @status.update!
    end

    def self.delete(name)
      queue_path = "queue/#{name}"

      stat = File.stat(queue_path)

      # Throw in the inode for uniqueness
      new_queue_path = "queue/#{name}.deleted.#{stat.ino}"

      FileUtils.mv(queue_path, new_queue_path)
    end

    def self.create(options,config_path=nil)
      # Create a directories and config
      queue_path = "queue/#{options['name']}"
      FileUtils.mkdir_p(queue_path)
      FileUtils.mkdir_p(queue_path + '/prep')
      FileUtils.mkdir_p(queue_path + '/que')
      FileUtils.mkdir_p(queue_path + '/run')
      FileUtils.mkdir_p(queue_path + '/pause')
      RQ::HashDir.make(queue_path + '/done')
      RQ::HashDir.make(queue_path + '/relayed')
      FileUtils.mkdir_p(queue_path + '/err')

      if config_path
        old_path = Pathname.new(config_path).realpath.to_s
        File.symlink(old_path, queue_path + '/config.json')
      else
        # Write config to dir
        File.open(queue_path + '/config.json', "w") do |f|
          f.write(options.to_json)
        end
      end
      RQ::Queue.start_process(options)
    end

    def self.log(path, mesg)
      File.open(path + '/queue.log', "a") do |f|
        f.write("#{Process.pid} - #{Time.now} - #{mesg}\n")
      end
    end

    def self.start_process(options)
      # nice pipes writeup
      # http://www.cim.mcgill.ca/~franco/OpSys-304-427/lecture-notes/node28.html
      child_rd, parent_wr = IO.pipe

      child_pid = fork do
        # Restore default signal handlers from those inherited from queuemgr
        Signal.trap('TERM', 'DEFAULT')
        Signal.trap('CHLD', 'DEFAULT')
        Signal.trap('HUP', 'DEFAULT')

        queue_path = "queue/#{options['name']}"
        $0 = "[rq-que] [#{options['name']}]"
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
        rescue Exception
          self.log(queue_path, "Exception!")
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

      worker = Worker.new
      worker.qc = QueueClient.new(options['name'])
      worker.name = options['name']
      worker.status = 'RUNNING'
      worker.child_write_pipe = parent_wr
      worker.pid = child_pid
      worker.num_restarts = 0
      worker.options = options
      worker
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

    def self.validate_options(options)
      err = false

      if not err
        if options.include?('name')
          if (1..128).include?(options['name'].size)
            if options['name'].class != String
              resp = "json config has invalid name (not String)"
              err = true
            end
          else
            resp = "json config has invalid name (size)"
            err = true
          end
        else
          resp = 'json config is missing name field'
          err = true
        end
      end

      if not err
        if options.include?('num_workers')
          if not ( (1..128).include?(options['num_workers'].to_i) )
            resp = "json config has invalid num_workers field (out of range 1..128)"
            err = true
          end
        else
          resp = 'json config is missing num_workers field'
          err = true
        end
      end

      if not err
        if options.include?('script')
          if (1..1024).include?(options['script'].size)
            if options['script'].class != String
              resp = "json config has invalid script (not String)"
              err = true
            end
          else
            resp = "json config has invalid script (size)"
            err = true
          end
        else
          resp = 'json config is missing script field'
          err = true
        end
      end

      [err, resp]
    end

    def run_queue_script!(msg)
      msg_id = msg['msg_id']

      basename = @queue_path + "/run/" + msg_id
      job_path = File.expand_path(basename + '/job/')
      Dir.mkdir(job_path) unless File.exists?(job_path)

      # Identify executable to run, if there is no script, go oper down
      # Also, fix an old issue where we didn't deref the symlink when executing a script
      # This meant that a script would see a new directory on a code deploy if that 
      # script lived under a symlinked path
      script_path = Pathname.new(@config.script).realpath.to_s
      if (not File.exists?(script_path)) && (not File.executable?(script_path))
        log("ERROR - QUEUE SCRIPT - not there or runnable #{script_path}")
        if @status.oper_status != 'SCRIPTERROR'
          @status.set_daemon_status('SCRIPTERROR')
          log("SCRIPTERROR - DAEMON STATUS is set to SCRIPTERROR")
          log("OPER STATUS is now: #{@status.oper_status}")
        end
        return
      elsif @status.oper_status == 'SCRIPTERROR'
        @status.set_daemon_status('UP')
        log("SCRIPTERROR FIXED - DAEMON STATUS is set to UP")
        log("OPER STATUS is now: #{@status.oper_status}")
      end

      #log("0 child process prep step for runnable #{script_path}")
      # 0 = stdin, 1 = stdout, 2 = stderr, 4 = pipe
      #
      parent_rd, child_wr = IO.pipe
      child_rd, parent_wr = IO.pipe

      log("1 child process prep step for runnable #{script_path}")
      #log("1 child process prep step for runnable #{job_path}")

      child_pid = fork do
        # Setup env
        $0 = "[rq-msg] [#{@name}] [#{msg_id}]"
        begin

          #child only code block

          Dir.chdir(job_path)   # Chdir to child path

          # TODO: log level
          #RQ::Queue.log(job_path, "child process prep step for runnable #{script_path}")

          #RQ::Queue.log(job_path, "post fork - parent rd pipe fd: #{parent_rd.fileno}")
          #RQ::Queue.log(job_path, "post fork - child wr pipe fd: #{child_wr.fileno}")

          #RQ::Queue.log(job_path, "post fork - child rd pipe fd: #{child_rd.fileno}")
          #RQ::Queue.log(job_path, "post fork - parent wr pipe fd: #{parent_wr.fileno}")

          # WE MUST DO THIS BECAUSE WE MAY GET PIPE FDs IN THE 3-4 RANGE
          # THIS GIVES US HIGHER # FDs SO WE CAN SAFELY CLOSE
          child_wr_fd = child_wr.fcntl(Fcntl::F_DUPFD)
          child_rd_fd = child_rd.fcntl(Fcntl::F_DUPFD)

          #RQ::Queue.log(job_path, "post fork - child_wr_fd pipe fd: #{child_wr_fd}")
          #RQ::Queue.log(job_path, "post fork - child_rd_fd pipe fd: #{child_rd_fd}")

          parent_rd.close
          parent_wr.close

          # Unix house keeping
          #self.close_all_fds([child_wr.fileno])

          #... the pipe fd will get closed on exec

          # child_wr
          IO.for_fd(3).close rescue nil
          fd = IO.for_fd(child_wr_fd).fcntl(Fcntl::F_DUPFD, 3)
          RQ::Queue.log(job_path, "Error duping fd for 3 - got #{fd}") unless fd == 3
          IO.for_fd(child_wr_fd).close rescue nil

          # child_rd
          IO.for_fd(4).close rescue nil
          fd = IO.for_fd(child_rd_fd).fcntl(Fcntl::F_DUPFD, 4)
          RQ::Queue.log(job_path, "Error duping fd for 4 - got #{fd}") unless fd == 4
          IO.for_fd(child_rd_fd).close rescue nil


          f = File.open(job_path + "/stdio.log", "a")
          pfx = "#{Process.pid} - #{Time.now} -"
          f.write("\n#{pfx} RQ START - #{script_path}\n")
          f.flush

          #RQ::Queue.log(job_path, "stdio.log has fd of #{f.fileno}")
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

          #RQ::Queue.log(job_path, 'post stdio re-assigning') unless fd == 2
          (5..32).each do |io|
            io = IO.for_fd(io) rescue nil
            next unless io
            io.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
          end
          #RQ::Queue.log(job_path, 'post FD_CLOEXEC') unless fd == 2

          #RQ::Queue.log(job_path, "running #{script_path}")

          load_aliases_config()

          ENV["RQ_SCRIPT"] = @config.script
          ENV["RQ_REALSCRIPT"] = script_path
          ENV["RQ_HOST"] = "http://#{@host}:#{@port}/"
          ENV["RQ_HOSTNAMES"] = @hostnames.join(" ")
          ENV["RQ_DEST"] = gen_full_dest(msg)['dest']
          ENV["RQ_DEST_QUEUE"] = gen_full_dest(msg)['queue']
          ENV["RQ_MSG_ID"] = msg_id
          ENV["RQ_FULL_MSG_ID"] = gen_full_msg_id(msg)
          ENV["RQ_MSG_DIR"] = job_path
          ENV["RQ_PIPE"] = "3"  # DEPRECATED
          ENV["RQ_WRITE"] = "3" # USE THESE INSTEAD
          ENV["RQ_READ"] = "4"
          ENV["RQ_COUNT"] = msg['count'].to_s
          ENV["RQ_PARAM1"] = msg['param1']
          ENV["RQ_PARAM2"] = msg['param2']
          ENV["RQ_PARAM3"] = msg['param3']
          ENV["RQ_PARAM4"] = msg['param4']
          ENV["RQ_ORIG_MSG_ID"] = msg['orig_msg_id']
          ENV["RQ_FORCE_REMOTE"] = "1" if msg['force_remote']

          # Set env vars specified in queue config file
          if @config.env_vars
            @config.env_vars.each do |varname,value|
              ENV[varname] = value unless varname.match(/^RQ_/) # Don't let the config override RQ-specific env vars though
            end
          end

          # unset RUBYOPT so it doesn't reinitialize the client ruby's GEM_HOME, etc.
          ENV.delete("RUBYOPT")

          # TODO
#          RQ::Queue.log(job_path, "set ENV now executing #{msg.inspect}")

          # Setting priority to BATCH mode
          Process.setpriority(Process::PRIO_PROCESS, 0, 19)

          # TODO
          #RQ::Queue.log(job_path, "set ENV, now executing #{script_path}")

          # bash -lc will execute the command but first re-initializing like a new login (reading .bashrc, etc.)
          exec_prefix = @config.exec_prefix || "bash -lc "
          if exec_prefix.empty?
            #RQ::Queue.log(job_path, "exec path: #{script_path}")
            exec(script_path, "")
          else
            #RQ::Queue.log(job_path, "exec path: #{exec_prefix + script_path}")
            exec(exec_prefix + script_path)
          end
        rescue
          RQ::Queue.log(job_path, $!)
          RQ::Queue.log(job_path, $!.backtrace)
          raise
        end
      end

      #parent only code block
      child_wr.close
      child_rd.close

      if child_pid == nil
        parent_rd.close
        log("ERROR failed to run child script: queue_path, $!")
        return nil
      end

      msg['child_pid'] = child_pid
      msg['child_read_pipe'] = parent_rd
      msg['child_write_pipe'] = parent_wr
      write_msg_process_id(msg_id, child_pid)
    end


    def init_socket
      # Show pid
      File.unlink(@queue_path + '/queue.pid') rescue nil
      File.open(@queue_path + '/queue.pid', "w") do |f|
        f.write("#{Process.pid}\n")
      end

      # Setup IPC
      File.unlink(@queue_path + '/queue.sock') rescue nil
      @sock = UNIXServer.open(@queue_path + '/queue.sock')
    end

    def load_rq_config
      begin
        data = File.read(@rq_config_path + 'config.json')
        js_data = JSON.parse(data)
        @host = js_data['host']
        @port = js_data['port']
        true
      rescue
        false
      end
    end

    def load_aliases_config
      @hostnames = [ "http://#{@host}:#{@port}/" ]
      if File.exists?(@rq_config_path + 'aliases.json')
        begin
          data = File.read(@rq_config_path + 'aliases.json')
          js_data = JSON.parse(data)
          @hostnames.concat( js_data['hostnames'] || [] )
        rescue
          log($!)
          log("Invalid aliases.json. Could not parse.")
          return false
        end
      end
      return true
    end

    def load_config
      @config_check = Time.now
      @config_file = JSONConfigFile.new(File.join(@queue_path, 'config.json'))
      @config = sublimate_config(@config_file.conf)
    end

    def sublimate_config(conf)
      # TODO config validation
      new_config                 = QueueConfig.new
      new_config.name            = conf['name']
      new_config.script          = conf['script']
      new_config.num_workers     = conf['num_workers'].to_i
      new_config.exec_prefix     = conf['exec_prefix']
      new_config.env_vars        = conf['env_vars']
      new_config.coalesce        = !!(%w{true yes 1}.include? conf['coalesce'])
      new_config.coalesce_params = Hash[ (1..4).map {|x| [x, !!(conf["coalesce_param#{x}"].to_i == 1)]} ]
      new_config
    end

    # It is called right before check_msg
    def alloc_id(msg)
      # Simple time insertion system - should work since single threaded
      times = 0
      begin
        z = Time.now.getutc
        name = z.strftime("_%Y%m%d.%H%M.%S.") + sprintf("%03d", (z.tv_usec / 1000))
        #fd = IO::sysopen(@queue_path + '/mesgs/' + name, Fcntl::O_WRONLY | Fcntl::O_EXCL | Fcntl::O_CREAT)
        # There we have created a name and inode
        #IO.new(fd).close

        Dir.mkdir(@queue_path + "/prep/" + name)
        stat = File.stat(@queue_path + "/prep/" + name)
        new_name = z.strftime("%Y%m%d.%H%M.%S.") + sprintf("%03d.%d", (z.tv_usec / 1000), stat.ino)
        File.rename(@queue_path + "/prep/" + name, @queue_path + "/prep/" + new_name)
        @prep << new_name
        msg["msg_id"] = new_name
        return msg
      rescue Exception
        times += 1
        log("FATAL - couldn't ALLOC ID times: #{times} #{$!}")
        if times > 10
          log("FAILED TO ALLOC ID")
          return nil
        end
        sleep 0.001
        retry
      end
      nil  # fail
    end

    # This copies certain fields over and insures consistency in a new
    # message
    # It is called right after alloc_id
    def check_msg(msg, input)
      # Required parameter
      return false unless input.has_key?('dest')
      msg['dest'] = input['dest']

      # If orig_msg_id is set already, then use it
      # otherwise we initialize it with this msg
      msg['orig_msg_id'] = input['orig_msg_id'] || gen_full_msg_id(msg)
      msg['count'] = (input['count'] || 0).to_i
      msg['max_count'] = (input['max_count'] || 15).to_i

      # Copy only these keys from input message
      keys = %w(src param1 param2 param3 param4 post_run_webhook due force_remote)
      keys.each do |key|
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
        clean = msg.reject { |k,v| k == 'child_read_pipe' || k == 'child_pid' || k == 'child_write_pipe' }
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
        msg, basename = get_message(msg, from_state)
        return false unless File.exists? basename
        newname = @queue_path + "/que/" + msg_id
        File.rename(basename, newname)
        msg['state']  = 'que'
        msg['status'] = 'que'
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

    def is_duplicate?(msg1, msg2)
      (1..4).each do |x|
        if @config.coalesce_params[x] and msg1["param#{x}"] != msg2["param#{x}"]
          return false
        end
      end
      true
    end

    # Handle a message that does succeed
    # Put all of its dups into the done state
    def handle_dups_done(msg, new_state)
      if msg['dups']
        msg['dups'].each do |i|
          h = @temp_que_dups.delete(i)
          new_status = "duplicate #{gen_full_msg_id(msg)}"
          write_msg_status(i, new_status, 'que')
          h['status'] = new_state + " - " + new_status
          h['state'] = new_state
          store_msg(h, 'que')
          # TODO: refactor this
          basename = "#{@queue_path}/que/#{i}"
          RQ::HashDir.inject(basename, "#{@queue_path}/#{new_state}", i)
        end
        msg['dups'] = msg['dups'].map { |i| gen_full_msg_id({'msg_id' => i}) }
      end
    end

    # Handle a message that doesn't succeed
    def handle_dups_fail(msg)
      if msg['dups']
        msg['dups'].each do |i|
          h = @temp_que_dups.delete(i)
          h.delete('dup')
          @que.unshift(h)
        end
        msg.delete('dups')
      end
    end

    def handle_dups(msg)
      return unless @config.coalesce

      duplicates = @que.select { |i| is_duplicate?(msg, i) }

      return if duplicates.empty?

      log("#{msg['msg_id']} - found #{duplicates.length} dups ")
      # Collect all the dups into the msg and remove from the @que
      # also show parent in each dup
      msg['dups'] = []
      duplicates.each { |i|
        msg['dups'] << i['msg_id']
        @temp_que_dups[i['msg_id']] = i
        r = @que.delete(i)               # ordering here is important
        log("#{r['msg_id']} - removed from @que as dup")
        i['dup'] = gen_full_msg_id(msg)
      }
    end

    # This is similar to check_msg, but it works with a message that is already
    # in the system
    def copy_and_clean_msg(input, new_dest = nil)
      msg = {}
      msg['dest'] = new_dest || input['dest']

      # If orig_msg_id is set already, then use it
      # otherwise we initialize it with this msg
      msg['orig_msg_id'] = input['orig_msg_id']
      msg['count'] = 0
      msg['max_count'] = (input['max_count'] || 15).to_i

      # Copy only these keys from input message
      keys = %w(src param1 param2 param3 param4 post_run_webhook due)
      keys.each do |key|
        next unless input.has_key?(key)
        msg[key] = input[key]
      end

      return msg
    end

    def run_job(msg, from_state = 'que')
      msg_id = msg['msg_id']
      begin
        basename = File.join(@queue_path, from_state, msg_id)
        newname = File.join(@queue_path, 'run', msg_id)
        File.rename(basename, newname)
      rescue
        log("FATAL - couldn't run message #{msg_id}")
        log("        [ #{$!} ]")

        # Remove the job from the queue. This may leave things in que state that
        # will be attempted again after a restart, but avoids the job jamming
        # the top of the queue. TODO: move the job to the err queue?
        @que.delete(msg)
        return false
      end

      # Put in run queue
      @que.delete(msg)
      @run.unshift(msg)

      handle_dups(msg)

      run_queue_script!(msg)
    end

    def lookup_msg(msg, state = 'prep', options={:consistency => true})
      msg_id = msg['msg_id']
      basename = nil
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
          if not Dir.glob("#{@queue_path}/que/#{msg_id}").empty?
            state = 'que'
            break
          end
          if @run.find { |o| o['msg_id'] == msg_id }
            state = 'run'
            break
          end
          if RQ::HashDir.exist("#{@queue_path}/done", msg_id)
            state = 'done'
            basename = RQ::HashDir.path_for("#{@queue_path}/done", msg_id)
            break
          end
          if RQ::HashDir.exist("#{@queue_path}/relayed", msg_id)
            state = 'relayed'
            basename = RQ::HashDir.path_for("#{@queue_path}/relayed", msg_id)
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
        basename ||= @queue_path + "/#{state}/" + msg_id
      end
      if options[:consistency]
        if not File.exists?(basename)
          log("WARNING - serious queue inconsistency #{msg_id}")
          log("WARNING - #{msg_id} in memory but not on disk")
          return false
        end
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

    def clone_msg(msg)
      resp = nil

      state = lookup_msg(msg, '*')
      return resp unless state
      return resp unless ['err', 'relayed', 'done'].include? state


      old_msg, old_basename = get_message(msg, state)

      new_msg = { }
      if alloc_id(new_msg) and check_msg(new_msg, old_msg)
        # check_msg copies only required fields, but still copies count
        # so we delete that as well
        new_msg['count'] = 0
        new_msg['cloned_from'] = old_msg['msg_id']

        # Now check for, and copy attachments
        # Assumes that original message guaranteed attachment integrity
        new_basename = @queue_path + "/prep/" + new_msg['msg_id']

        if File.directory?(old_basename + "/attach/")
          ents = Dir.entries(old_basename + "/attach/").reject {|i| i.index('.') == 0 }
          if not ents.empty?
            # simple check for attachment dir
            old_attach_path = old_basename + '/attach/'
            new_attach_path = new_basename + '/attach/'
            Dir.mkdir(new_attach_path)

            ents.each do |ent|
              # Now clone attachments by hard_linking to them in new message
              new_path = new_attach_path + ent
              old_path = old_attach_path + ent
              File.link(old_path, new_path)
            end
          end
        end

        store_msg(new_msg)
        que(new_msg)
        msg_id = gen_full_msg_id(new_msg)
        resp = msg_id
      end
      resp
    end

    def get_message(params, state,
                    options={ :read_message => true,
                              :check_attachments => true})
      if ['done', 'relayed'].include? state
        basename = RQ::HashDir.path_for("#{@queue_path}/#{state}", params['msg_id'])
      else
        basename = @queue_path + "/#{state}/" + params['msg_id']
      end

      msg = nil
      begin
        if options[:read_message]
          data = File.read(basename + "/msg")
          msg = JSON.parse(data)
        else
          msg = {}
        end
        msg['status'] = state
        msg['state'] = state
        if File.exists?(basename + "/status")
          xtra_data = File.read(basename + "/status")
          xtra_status = JSON.parse(xtra_data)
          msg['status'] += " - #{xtra_status['job_status']}"
        end

        # Now check for attachments
        if options[:read_message] && options[:check_attachments] && File.directory?(basename + "/attach/")
          cwd = Dir.pwd
          ents = Dir.entries(basename + "/attach/").reject {|i| i.index('.') == 0 }
          if not ents.empty?
            msg['_attachments'] = { }
            ents.each do |ent|
              msg['_attachments'][ent] = { }
              path = "#{basename}/attach/#{ent}"
              md5, size = file_md5(path)
              msg['_attachments'][ent]['md5'] = md5
              msg['_attachments'][ent]['size'] = size
              msg['_attachments'][ent]['path'] = cwd + '/' + path
            end
          end
        end

      rescue
        msg = nil
        log("Bad message in queue: #{basename}")
        log("        [ #{$!} ]")
      end

      return [msg, basename]
    end

    def gen_full_msg_id(msg)
      full_name = "http://#{@host}:#{@port}/q/#{@name}/#{msg['msg_id']}"
      return full_name
    end

    def gen_full_dest(msg)
      res = {
        'dest' => "http://#{@host}:#{@port}/q/#{msg['dest']}/",
        'queue' => msg['dest']
      }

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
        name_test = name.tr('~?[]%|$&<>', '*')
        if name_test.index("*")
          return [false, "Attachment name has invalid character. not allowed: #{name}"]
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
        File.unlink(tmp_new_path) rescue nil       # Insure tmp_new_path is clear
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

    def del_attach_msg(msg)
      msg_id = msg['msg_id']
      attach_name = msg['attachment_name']
      # validate attachment
      result = [false, 'Unknown error']
      begin
        basename = @queue_path + "/prep/" + msg_id
        return [false, "No message on disk"] unless File.exists? basename

        # simple check for attachment dir
        attach_path = basename + '/attach/'
        return [false, "No attach directory for msg"] unless File.exists?(attach_path)

        new_path = attach_path + attach_name
        return [false, "No attachment with that named for msg"] unless File.exists?(new_path)

        File.unlink(new_path)

        result = ["ok", "Attachment deleted successfully"]
      rescue
        log("FATAL - couldn't delete attachment #{attach_name} from message #{msg_id}")
        log("        [ #{$!} ]")
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

      # run msgs just put back into que
      basename = @queue_path + '/run/'
      messages = Dir.entries(basename).reject {|i| i.index('.') == 0 }
      messages.each do |mname|
        begin
          File.rename(basename + mname, @queue_path + '/que/' + mname)
        rescue
          log("Bad message in run queue: #{mname}")
          next
        end
      end

      # que has actual messages copied
      basename = @queue_path + '/que/'
      messages = Dir.entries(basename).reject {|i| i.index('.') == 0 }

      messages.sort!.reverse!

      messages.each do |mname|
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

    end

    def handle_status_read(msg)
      msg_id = msg['msg_id']
      child_io = msg['child_read_pipe']
      child_pid = msg['child_pid']

      log("#{child_pid}: Reading status from child")
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

      child_msgs.each do |child_msg|
        parts = child_msg.split(" ", 2)

        # Always write message status
        write_msg_status(msg['msg_id'], parts[1])

        # BELOW - changed my mind about moving the message into its new
        # queue. Why? What if the msg says it is done, but the process
        # doesn't exit cleanly. That would be bad form. The safe thing
        # to do is to re-run the process if there is a crash (for now)

        # Also, we record the timestamp of this message in the completion
        # This allows us to notice any processes that have failed to terminate
        # and then kill them down the road.

        log("#{child_pid}: child msg came in: #{child_msg}")
        if (parts[0] != "run")
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
            due,reason = parts[1].split('-',2)
            msg['due'] = Time.now.to_i + due.to_i
            msg['count'] = msg.fetch('count', 0) + 1
            store_msg(msg, 'run')
            # *** THIS ONE IS DIFFERENT ***
            # We need to set the messages 'due' time. This is safe
            # since we are in the run queue, and we want to record
            # this to disk before moving on
          end

          ##############################################################################
          # *** THIS ONE IS (((REALLY))) DIFFERENT ***
          # We need to take an action instead of expecting an exit
          # that will arrive soon.
          if parts[0] == 'dup'
            due,future,new_dest = parts[1].split('-',3)
            new_due = Time.now.to_i + due.to_i

            if new_dest.index('http') == 0
              que_name = 'relay'
            else
              que_name = new_dest
            end

            qc = RQ::QueueClient.new(que_name)
            if not qc.exists?
              log("#{@name}:#{Process.pid} couldn't DUP message - #{que_name} not available.")
              msg['child_write_pipe'].syswrite("fail couldn\'t connect to queue - #{que_name}\n")
              return
            end

            # Copy orig message
            msg_copy = copy_and_clean_msg(msg, new_dest)
            msg_copy['due'] = new_due

            basename = @queue_path + "/run/" + msg['msg_id']

            # Now see if there are any attachments
            attachments = []

            if File.directory?(basename + "/attach/")
              ents = Dir.entries(basename + "/attach/").reject {|i| i.index('.') == 0 }
              if not ents.empty?
                # Cool, lets normalize the paths
                full_path = File.expand_path(basename + "/attach/")

                attachments = ents.map { |e| "#{full_path}/#{e}" }
              end
            end

            if attachments.empty?
              result = qc.create_message(msg_copy)
              if result[0] != 'ok'
                log("#{@name}:#{Process.pid} couldn't DUP message - #{result[1]}")
                msg['child_write_pipe'].syswrite("fail dup failed - #{result[1]}\n")
                return
              end
              log("#{@name}:#{Process.pid} DUP message #{msg['msg_id']}-> #{result[1]}")
              msg['child_write_pipe'].syswrite("ok #{result[1]}\n")
            else
              result = qc.prep_message(msg_copy)
              if result[0] != 'ok'
                log("#{@name}:#{Process.pid} couldn't DUP message - #{result[1]}")
                msg['child_write_pipe'].syswrite("fail dup failed - prep fail #{result[1]}\n")
                return
              end

              # The short msg_id
              que_msg_id = result[1][/\/q\/[^\/]+\/([^\/]+)/, 1]

              attachments.each do |path|
                r2 = qc.attach_message({'msg_id' => que_msg_id, 'pathname' => path})
                if r2[0] != 'ok'
                  log("#{@name}:#{Process.pid} couldn't DUP message - #{r2[1]}")
                  msg['child_write_pipe'].syswrite("fail dup failed - attach fail #{r2[1]}\n")
                  return
                end
              end

              r3 = qc.commit_message({'msg_id' => que_msg_id})
              if r3[0] != 'ok'
                log("#{@name}:#{Process.pid} couldn't DUP message - #{r3[1]}")
                msg['child_write_pipe'].syswrite("fail dup failed - commit fail #{r3[1]}\n")
                return
              end
              log("#{@name}:#{Process.pid} DUP message with ATTACH #{msg['msg_id']}-> #{result[1]}")
              msg['child_write_pipe'].syswrite("ok #{result[1]}\n")
            end

          end
          ##############################################################################
        end
      end

      return true
    end

    def write_msg_status(msg_id, mesg, state = 'run')
      # Write message to disk
      begin
        data = { 'job_status' => mesg }.to_json
        basename = @queue_path + "/#{state}/" + msg_id + "/status"
        File.open(basename + '.tmp', 'w') { |f| f.write(data) }
        File.rename(basename + '.tmp', basename)
      rescue
        log("FATAL - couldn't write status message")
        log("        [ #{$!} ]")
        return false
      end

      return true
    end

    def write_msg_process_id(msg_id, pid)
      # Write message pid to disk
      begin
        basename = "#{@queue_path}/run/#{msg_id}/pid"
        File.open(basename + '.tmp', 'w') { |f| f.write(pid.to_s) }
        File.rename(basename + '.tmp', basename)
      rescue
        log("FATAL - couldn't write message pid file")
        log("        [ #{$!} ]")
        return false
      end

      return true
    end

    def remove_msg_process_id(msg_id, state = 'run')
      basename = "#{@queue_path}/run/#{msg_id}/pid"
      FileUtils.rm_rf(basename)
    end

    def log(mesg)
      File.open(@queue_path + '/queue.log', "a") do |f|
        f.write("#{Process.pid} - #{Time.now} - #{mesg}\n")
      end
    end

    def shutdown!
      log("Received shutdown")
      Process.exit! 0
    end

    def run_scheduler!
      @wait_time = 5

      @status.update!

      # This could be DOWN, PAUSE, SCRIPTERROR
      return unless @status.oper_status == 'UP'

      # Are we arleady running max workers
      active_count = @run.inject(0) do |acc, o|
        if o.has_key?('child_pid')
          acc = acc + 1
        end
        acc
      end

      if active_count >= @config.num_workers
        #log("Already running #{active_count} config is max: #{@config['num_workers']}")
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
      ready_msg = @que.min {|a,b| a['due'].to_f <=> b['due'].to_f }

      delta = ready_msg['due'].to_f - Time.now.to_f

      log("Delta: #{delta}")
      # If it is time to wait, then run
      if delta > 0
        if delta < 60  # Set timeout to be this, vs default of 60 set above
          @wait_time = delta
        end
        return
      end

      log("Running #{ready_msg['msg_id']} - delta #{delta}")
      # Looks like it is time to run now...
      run_job(ready_msg)
      run_scheduler!   # Tail recursion, fail me now, I'm in Ruby
                       # So, lets hope the load isn't too high
                       # If it is, then we will loop like crazy
    end

    def run_loop
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
        io_list << @signal_hup_rd
        #log('sleeping') if @wait_time == 60
        begin
          ready = IO.select(io_list, nil, nil, @wait_time)
        rescue Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::ECONNABORTED, Errno::EPROTO, Errno::EINTR
          log("error on SELECT #{$!}")
          retry
        end

        # TODO: handle children that have reported a state change, but have
        #       not exited

        now = Time.now
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
            elsif io.fileno == @parent_pipe.fileno
              log("QUEUE #{@name} of PID #{Process.pid} noticed parent close exiting...")
              shutdown!
              next
            elsif io.fileno == @signal_hup_rd.fileno
              log("QUEUE #{@name} of PID #{Process.pid} noticed SIGNAL HUP")

              # Force a new config check
              @config_check = now - 10

              # Linux Doesn't inherit and BSD does... recomended behavior is to set again
              flag = 0xffffffff ^ File::NONBLOCK
              if defined?(Fcntl::F_GETFL)
                flag &= @signal_hup_rd.fcntl(Fcntl::F_GETFL)
              end
              @signal_hup_rd.fcntl(Fcntl::F_SETFL, flag)
              dat = do_read(@signal_hup_rd, 1)
              log("Strange Result from HUP signal pipe.") if dat.size != 1
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
                orig_msg_id = msg['orig_msg_id']

                # Ok, close the pipe on our end
                msg['child_read_pipe'].close
                msg.delete('child_read_pipe')
                msg['child_write_pipe'].close
                msg.delete('child_write_pipe')

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
                  if msg['count'] >= msg['max_count']
                    new_state = 'err'
                    log("RESEND hit max: #{msg['count']} / #{msg['max_count']} - #{msg_id}")
                    write_msg_status(msg_id, "HIT MAX RESEND COUNT - MOVING TO ERR" )
                  else
                    new_state = 'que'
                  end
                end

                if new_state == nil
                  # log a message
                  write_msg_status(msg_id, "PROCESS EXITED IMPROPERLY - MOVING TO ERR- Expected #{completion[1]} - and - status #{res.inspect}" )
                  write_msg_status(msg_id, "PROCESS EXITED IMPROPERLY" )
                  new_state = 'err'
                end

                # Process has exited, so it must change states at this point
                # Move to relay dir and update in-memory data structure
                begin
                  basename = "#{@queue_path}/run/#{msg_id}"
                  raise unless File.exists? basename
                  remove_msg_process_id(msg_id)
                  if ['done', 'relayed'].include? new_state
                    handle_dups_done(msg, new_state)
                    store_msg(msg, 'run') # store message since it made it to done and we want the 'dups' field to live
                    RQ::HashDir.inject(basename, "#{@queue_path}/#{new_state}", msg_id)
                  else
                    handle_dups_fail(msg)
                    store_msg(msg, 'run') # store message since it failed to make it to done and
                                          # we want the 'dups' field to be removed
                    newname = "#{@queue_path}/#{new_state}/#{msg_id}"
                    File.rename(basename, newname)
                  end
                rescue
                  log("FATAL - couldn't move from 'run' to '#{new_state}' #{msg_id}")
                  log("        [ #{$!} ]")
                  next
                end

                if ['err', 'done', 'relayed'].include? new_state
                  # Send a webhook if there is a web hook
                  if msg.include? 'post_run_webhook'
                    msg['post_run_webhook'].each do |wh|
                      webhook_message(wh, msg, new_state)
                    end
                  end
                end

                log("Prior to resend: run - #{@run.length} que - #{@que.length} completed - #{@completed.length}")
                # Remove from completion
                @completed.delete(completion)
                # Remove from run
                @run = @run.reject { |i| i['msg_id'] == msg_id }
                # TODO; a simple delete would suffice here

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
                sleep 0.001
              end

            else
              log("QUEUE #{@name} of PID #{Process.pid} noticed fd close on fd #{io.fileno}...NO CHILD ON RECORD?")
            end
          end
        end

        # Check if it has been > 5 seconds since last config file check
        if (now - @config_check) > 5
          if @config_file.check_for_change == JSONConfigFile::CHANGED
            log('Config file changed. Using new config')
            @config = sublimate_config(@config_file.conf)
          end
          @config_check = now
        end

      end
    end

    # Inject a message into 'que' state
    def webhook_message(url, msg, new_state)
      require 'code/queueclient'
      qc = RQ::QueueClient.new('webhook')

      msg_id = gen_full_msg_id(msg)

      if not qc.exists?
        log("QUEUE #{@name} of PID #{Process.pid} couldn't que webhook for msg_id: #{msg_id}")
        return
      end

      # Copy orig message
      msg_copy = msg.clone
      msg_copy['msg_id'] = msg_id
      msg_copy['state'] = new_state
      msg_copy.delete 'status'
      msg_copy.delete '_attachments'

      # Construct message
      mesg = {}
      mesg['dest'] = 'webhook'
      mesg['param1'] = url
      mesg['param2'] = msg_copy.to_json
      result = qc.create_message(mesg)
      if result[0] != 'ok'
        log("QUEUE #{@name} of PID #{Process.pid} couldn't que webhook: #{result[0]} #{result[1]} for msg_id: #{msg_id}")
      end
    end

    def do_read(client, numr = 32768)
      begin
        dat = client.sysread(numr)
      rescue Errno::EINTR  # Ruby threading can cause an alarm/timer interrupt on a syscall
        retry
      rescue EOFError
        #TODO: add debug mode
        #puts "Got an EOF from socket read"
        return nil
      rescue Errno::ECONNRESET,Errno::EPIPE,Errno::EINVAL,Errno::EBADF
        puts "Got an #{$!} from socket read"
        exit! 0
      end
      dat
    end

    def read_packet(sock)
      protocol = do_read(sock, 4)

      if protocol != 'rq1 '
        log("REQ - Invalid protocol - bad ver")
        return nil
      end

      size_str = do_read(sock, 9)

      if size_str[-1..-1] != " "
        log("REQ - Invalid protocol - bad size #{size_str}")
        return nil
      end

      size = size_str.to_i
      log("REQ - size #{size}")

      result = UnixRack::Socket.read_sock_num_bytes(sock, size)

      if result[0] == false
        log("REQ - Invalid packet - didn't receive contents")
        return nil
      end

      result[1]
    end

    def send_packet(sock, resp)
      log_msg = resp.length > 80 ? "#{resp[0...80]}..." : resp
      log("RESP [ #{resp.length}  #{log_msg} ]")
      sock_msg = sprintf("rq1 %08d %s", resp.length, resp)
      UnixRack::Socket.write_buff(sock, sock_msg)
      sock.close
    end

    def handle_request(sock)

      packet = read_packet(sock)

      return if packet == nil

      log("REQ [ #{packet} ]")

      if packet.index('ping ') == 0
        resp = [ "pong" ].to_json
        send_packet(sock, resp)
        return
      end

      if packet.index('uptime ') == 0
        resp = [(Time.now - @start_time).to_i, ].to_json
        send_packet(sock, resp)
        return
      end

      if packet.index('config ') == 0
        # Sadly there's no struct-to-hash method until Ruby 2.0
        resp = [ 'ok', Hash[@config.each_pair.to_a]].to_json
        send_packet(sock, resp)
        return
      end

      if packet.index('status') == 0
        @status.update!
        resp = [ @status.admin_status, @status.oper_status ].to_json
        send_packet(sock, resp)
        return
      end

      if packet.index('shutdown') == 0
        resp = [ 'ok' ].to_json
        send_packet(sock, resp)
        shutdown!
        return
      end

      # IF queue is admin_status DOWN, no need to respond to any of the
      # following messages (Note: there are other states, this is a hard DOWN)
      if @status.admin_status == 'DOWN'
        resp = [ "fail", "oper_status: DOWN"].to_json
        send_packet(sock, resp)
        return
      end

      if packet.index('create_message') == 0
        json = packet.split(' ', 2)[1]
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
        send_packet(sock, resp)
        return
      end

      if packet.index('single_que') == 0
        json = packet.split(' ', 2)[1]
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
        send_packet(sock, resp)
        return
      end

      if packet.index('num_messages') == 0
        status = { }
        status['prep']     = @prep.length
        status['que']      = @que.length
        status['run']      = @run.length
        status['pause']    = []
        status['done']     = RQ::HashDir.num_entries(@queue_path + "/done")
        status['relayed']  = RQ::HashDir.num_entries(@queue_path + "/relayed/")
        status['err']      = Dir.entries(@queue_path + "/err/").reject {|i| i.index('.') == 0 }.length

        resp = status.to_json
        send_packet(sock, resp)
        return
      end

      if packet.index('messages') == 0
        json = packet.split(' ', 2)[1]
        options = JSON.parse(json)
        if not options.has_key?('state')
          resp = [ "fail", "lacking 'state' field"].to_json
          send_packet(sock, resp)
          return
        end
        if options['state'] == 'prep'
           status = @prep
        elsif options['state'] == 'que'
          status = @que.map { |m| [m['msg_id'], m['due']] }
        elsif options['state'] == 'run'
          status = @run.map { |m| [m['msg_id'], m['status']] }
        elsif options['state'] == 'done'
          status = RQ::HashDir.entries(@queue_path + "/done", options['limit'])
        elsif options['state'] == 'relayed'
          status = RQ::HashDir.entries(@queue_path + "/relayed/", options['limit'])
        elsif options['state'] == 'err'
          status = Dir.entries(@queue_path + "/err/").reject {|i| i.index('.') == 0 }
        else
          status = [ "fail", "invalid 'state' field (#{options['state']})"]
        end

        resp = status.to_json
        send_packet(sock, resp)
        return
      end

      if packet.index('prep_message') == 0
        json = packet.split(' ', 2)[1]
        options = JSON.parse(json)

        msg = { }
        if alloc_id(msg) and check_msg(msg, options)
          store_msg(msg)
          msg_id = gen_full_msg_id(msg)
          resp = [ "ok", msg_id ].to_json
        else
          resp = [ "fail", "unknown reason"].to_json
        end
        send_packet(sock, resp)
        return
      end

      if packet.index('attach_message') == 0
        json = packet.split(' ', 2)[1]
        options = JSON.parse(json)

        if not options.has_key?('msg_id')
          resp = [ "fail", "lacking 'msg_id' field"].to_json
          send_packet(sock, resp)
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
          resp = [ "fail", "cannot find message"].to_json
        end
        send_packet(sock, resp)
        return
      end

      if packet.index('delete_attach_message') == 0
        # Params: msg_id, attachment_name
        json = packet.split(' ', 2)[1]
        options = JSON.parse(json)

        if not options.has_key?('msg_id')
          resp = [ "fail", "lacking 'msg_id' field"].to_json
          send_packet(sock, resp)
          return
        end

        state = lookup_msg(options, '*')
        if state
          if state != 'prep'
            resp = [ "fail", "msg not in prep" ].to_json
          else
            success, del_attach_result = del_attach_msg(options)
            resp = [ success, del_attach_result ].to_json
          end
        else
          resp = [ "fail", "msg not found" ].to_json
        end
        send_packet(sock, resp)
        return
      end

      if packet.index('commit_message') == 0
        json = packet.split(' ', 2)[1]
        options = JSON.parse(json)

        if not options.has_key?('msg_id')
          resp = [ "fail", "lacking 'msg_id' field"].to_json
          send_packet(sock, resp)
          return
        end

        resp = [ "fail", "unknown reason"].to_json

        if lookup_msg(options)
          if que(options)
            resp = [ "ok", "msg commited" ].to_json
          end
        else
          resp = [ "fail", "cannot find message"].to_json
        end

        send_packet(sock, resp)
        return
      end

      if packet.index('get_message ') == 0
        json = packet.split(' ', 2)[1]
        options = JSON.parse(json)

        if not options.has_key?('msg_id')
          resp = [ "fail", "lacking 'msg_id' field"].to_json
          send_packet(sock, resp)
          return
        end

        resp = [ "fail", "unknown reason"].to_json

        state = lookup_msg(options, '*')
        if state
          msg, msg_path = get_message(options, state)
          if msg
            resp = [ "ok", msg ].to_json
          else
            resp = [ "fail", "msg couldn't be read" ].to_json
          end
        else
          resp = [ "fail", "msg not found" ].to_json
        end

        send_packet(sock, resp)
        return
      end

      if packet.index('get_message_state ') == 0
        json = packet.split(' ', 2)[1]
        options = JSON.parse(json)

        if not options.has_key?('msg_id')
          resp = [ "fail", "lacking 'msg_id' field"].to_json
          send_packet(sock, resp)
          return
        end

        resp = [ "fail", "unknown reason"].to_json

        # turn off consistency for a little more speed
        state = lookup_msg(options, '*', {:consistency => false})
        if state
          resp = [ "ok", state ].to_json
        else
          resp = [ "fail", "msg not found" ].to_json
        end

        send_packet(sock, resp)
        return
      end

      if packet.index('get_message_status ') == 0
        json = packet.split(' ', 2)[1]
        options = JSON.parse(json)

        if not options.has_key?('msg_id')
          resp = [ "fail", "lacking 'msg_id' field"].to_json
          send_packet(sock, resp)
          return
        end

        resp = [ "fail", "unknown reason"].to_json

        # turn off consistency for a little more speed
        state = lookup_msg(options, '*', {:consistency => false})
        if state
          msg, msg_path = get_message(options,
                                      state,
                                      {:read_message => false})
          if msg
            resp = [ "ok", msg ].to_json
          else
            resp = [ "fail", "msg couldn't be read" ].to_json
          end
        else
          resp = [ "fail", "msg not found" ].to_json
        end

        send_packet(sock, resp)
        return
      end

      if packet.index('delete_message') == 0
        json = packet.split(' ', 2)[1]
        options = JSON.parse(json)

        if not options.has_key?('msg_id')
          resp = [ "fail", "lacking 'msg_id' field"].to_json
          send_packet(sock, resp)
          return
        end

        resp = [ "fail", "unknown reason"].to_json

        if lookup_msg(options, '*')
          delete_msg!(options)
          resp = [ "ok", "msg deleted" ].to_json
        else
          resp = [ "fail", "msg not found" ].to_json
        end

        send_packet(sock, resp)
        return
      end

      if packet.index('run_message') == 0
        json = packet.split(' ', 2)[1]
        options = JSON.parse(json)

        if not options.has_key?('msg_id')
          resp = [ "fail", "lacking 'msg_id' field"].to_json
          send_packet(sock, resp)
          return
        end

        resp = [ "fail", "unknown reason"].to_json

        state = lookup_msg(options, '*')
        if state == 'que'
          # Jump to the front of the queue
          ready_msg = @que.min {|a,b| a['due'].to_f <=> b['due'].to_f }
          m = @que.find { |e| e['msg_id'] == options['msg_id'] }
          if (not m.nil?) and (not ready_msg.nil?)
            m['due'] = ready_msg['due'] - 1.0
            resp = [ "ok", "msg sent to front of run queue" ].to_json
          else
            resp = [ "fail", "cannot send message to run state" ].to_json
          end
        end

        send_packet(sock, resp)
        return
      end

      if packet.index('clone_message') == 0
        json = packet.split(' ', 2)[1]
        options = JSON.parse(json)

        if not options.has_key?('msg_id')
          resp = [ "fail", "lacking 'msg_id' field"].to_json
          send_packet(sock, resp)
          return
        end

        resp = [ "fail", "unknown reason"].to_json

        state = lookup_msg(options, '*')
        if state
          if ['err', 'relayed', 'done'].include? state
            msg_id = clone_msg(options)
            if msg_id
              resp = [ "ok", msg_id ].to_json
            else
              resp = [ "fail", "msg couldn't be cloned" ].to_json
            end
          else
            resp = [ "fail", "cannot clone message in #{state} state" ].to_json
          end
        else
          resp = [ "fail", "msg not found" ].to_json
        end

        send_packet(sock, resp)
        return
      end

      send_packet(sock, '[ "ERROR" ]')
      log("RESP [ ERROR ] - Unhandled message")
    end

  end
end
