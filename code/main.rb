require 'sinatra/base'
require 'erb'

require 'version'
require 'code/queuemgrclient'
require 'code/queueclient'
require 'code/errors'
require 'code/hashdir'
require 'code/overrides'

module RQ
  class Main < Sinatra::Base

    # This is almost identical to Rack::URLMap but without checking that
    # env['HTTP_HOST'] == env['SERVER_NAME'], and without support for
    # multiple mapped paths.
    class RelativeRoot
      def initialize(app, relative_root)
        @app = app
        @relative_root = relative_root.chomp('/')
        @match = Regexp.new("^#{Regexp.quote(@relative_root).gsub('/', '/+')}(.*)", nil, 'n')
      end

      def call(env)
        script_name = env['SCRIPT_NAME']
        path = env['PATH_INFO']

        m = @match.match(path.to_s)
        if m && (rest = m[1]) && (!rest || rest.empty? || rest[0] == ?/)
          env['SCRIPT_NAME'] = (script_name + @relative_root)
          env['PATH_INFO'] = rest
          @app.call(env)
        else
          [404, {"Content-Type" => "text/plain", "X-Cascade" => "pass"}, ["Not Found: #{path}"]]
        end

      ensure
        env['SCRIPT_NAME'] = script_name
        env['PATH_INFO'] = path
      end
    end

    enable :sessions
    set :session_secret, 'super secret'  # we are forking, so we must set

    # Enable erb templates with <%- newline trimming
    set :erb, :trim => '-'
    set :views, './code/views'

    # Let Sinatra handle static file service
    enable :static
    set :public_folder, './code/public'

    # Use the global Logger
    after do
      # Format adapted from Rack::CommonLogger
      $log.info %{%s - %s "%s %s %s" %d %d %s "%s" "%s"} % [
        request.ip || "-",
        env["REMOTE_USER"] || "-",
        request.request_method,
        request.fullpath,
        env["HTTP_VERSION"],
        status.to_s[0..3],
        request.content_length.to_i,
        request.media_type || "-",
        request.referer || "-",
        request.user_agent || "-",
      ]
    end

    def initialize(app=nil, config={})
      super(app)
      @allow_new_queue = config.fetch('allow_new_queue', false)
      @relative_root = config.fetch('relative_root', '/').chomp('/') + '/'
    end

    def self.to_app(config)
      relative_root = config.fetch('relative_root', '/').chomp('/') + '/'
      raise ArgumentError, 'relative_root must start with /' unless relative_root.start_with?('/')
      Rack::Builder.app do
        use RQ::Main::RelativeRoot, relative_root
        basic_auth = config['basic_auth']
        if basic_auth
          use Rack::Auth::Basic, basic_auth['realm'] do |username, password|
            basic_auth['users'][username] == password
          end
        end
        run RQ::Main.new(nil, config)
      end
    end

    helpers do
      def root
        @relative_root
      end

      def allow_new_queue?
        @allow_new_queue
      end

      def get_queueclient(name)
        # SPECIAL CASE - we allow relay and cleaner
        # No RQ should be connecting to another box's relay
        # However, users need the web ui to interact, so we think
        # this is safe and good for debugging/visiblity
        if File.exists?("./config/rq_router_rules.rb")
          if not ['relay', 'cleaner'].include?(name)
            name = 'rq_router'
          end
        end
        RQ::QueueClient.new(name)
      end

      def queuemgr
        @queuemgr ||= RQ::QueueMgrClient.new
      end

      def msgs_labels
        %w[prep que run err done relayed]
      end

      def flash(type, msg)
        h = session[:flash] || {}
        h[type] = msg
        session[:flash] = h
      end
    end

    before do
      val = session[:flash]
      @flash = val || {}
      session[:flash] = {}
    end

    # handle 404s
    not_found do
      status 404
      erb :not_found
    end

    get '/' do
      erb :main
    end

    get '/new_queue' do
      throw :halt, [403, "Queue creation not allowed at this time."] unless allow_new_queue?

      erb :new_queue
    end

    post '/new_queue' do
      throw :halt, [403, "Queue creation not allowed at this time."] unless allow_new_queue?
      # TODO: validation

      # This creates and starts a queue
      result = queuemgr.create_queue(params['queue'])
      flash :notice, "We got <code>#{params.inspect}</code> from form, and <code>#{result}</code> from QueueMgr"
      redirect "#{root}q/#{params['queue']['name']}"
    end

    post '/new_queue_link' do
      throw :halt, [403, "Queue creation not allowed at this time."] unless allow_new_queue?

      # This creates and starts a queue via a config file in json
      js_data = {}
      begin
        js_data = JSON.parse(File.read(params['queue']['json_path']))
      rescue
        p $!
        p "BAD config.json - could not parse"
        throw :halt, [404, "404 - Couldn't parse json file (#{params['queue']['json_path']})."]
        end
      result = queuemgr.create_queue_link(params['queue']['json_path'])
      #TODO - do the right thing with the result code
      flash :notice, "We got <code>#{params.inspect}</code> from form, and <code>#{result}</code> from QueueMgr"
      redirect "#{root}q/#{js_data['name']}"
    end

    post '/delete_queue' do
      # This creates and starts a queue
      result = queuemgr.delete_queue(params['queue_name'])
      flash :notice, "We got <code>#{params.inspect}</code> from form, and <code>#{result}</code> from QueueMgr"
      redirect root
    end

    get '/q.txt' do
      content_type 'text/plain', :charset => 'utf-8'
      erb :queue_list, :layout => false, :locals => {:queues => queuemgr.queues}
    end

    get '/q.json' do
      queuemgr.queues.to_json
    end

    get '/q/:name' do
      if params[:name].index(".txt")
        content_type 'text/plain', :charset => 'utf-8'
        return erb :queue_txt, :layout => false, :locals => { :qc => RQ::QueueClient.new(params[:name].split(".txt").first) }
      elsif params[:name].index(".json")
        if '.json' == params[:name][-5..-1]
          return erb :queue_json, :layout => false, :locals => { :qc => RQ::QueueClient.new(params[:name].split(".json").first) }
        end
      end

      if not queuemgr.running?
        throw :halt, [503, "503 - QueueMgr not running"]
      end

      begin
        qc = RQ::QueueClient.new(params[:name])
      rescue RQ::RqQueueNotFound
        throw :halt, [404, "404 - Queue not found"]
      end

      ok, config = qc.config
      erb :queue, :locals => { :qc => qc, :config => config }
    end

    get '/q/:name/done.json' do
      if not queuemgr.running?
        throw :halt, [503, "503 - QueueMgr not running"]
      end

      begin
        qc = RQ::QueueClient.new(params[:name])
      rescue RQ::RqQueueNotFound
        throw :halt, [404, "404 - Queue not found"]
      end

      limit = 10
      if params['limit']
        limit = params['limit'].to_i
      end
      result = qc.messages({'state' => 'done', 'limit' => limit})
      "#{result.to_json}"
    end

    get '/q/:name/new_message' do
      begin
        qc = RQ::QueueClient.new(params[:name])
      rescue RQ::RqQueueNotFound
        throw :halt, [404, "404 - Queue not found"]
      end

      overrides = RQ::Overrides.new(params['name'])
      erb :new_message, :layout => true, :locals => { :q_name => qc.name, :overrides => overrides }
    end

    post '/q/:name/new_message' do
      api_call = params.fetch('x_format', 'json')
      if api_call == 'html'
        prms = params['mesg'].clone
      else
        prms = JSON.parse(params['mesg'])
      end

      # Normalize some values
      if prms.has_key? 'post_run_webhook' and prms['post_run_webhook'].is_a? String
        # clean webhook input of any spaces
        # Ruby split..... so good!
        prms['post_run_webhook'] = prms['post_run_webhook'].split ' '
      end
      if prms.has_key? 'count'
        prms['count'] = prms['count'].to_i
      end
      if prms.has_key? 'max_count'
        prms['max_count'] = prms['max_count'].to_i
      end

      begin
        qc = get_queueclient(params[:name])
      rescue RQ::RqQueueNotFound
        throw :halt, [404, "404 - Queue not found"]
      end

      case prms.fetch('_method', 'commit')
      when 'prep'
        result = qc.prep_message(prms)
      when 'single_que'
        result = qc.single_que(prms)
      when 'commit'
        result = qc.create_message(prms)
      else
        throw :halt, [400, "400 - Invalid method param"]
      end

      if result == [ "fail", "status: DOWN"]
        throw :halt, [503, "503 - Service Unavailable - Operationally Down"]
      end

      if api_call == 'json'
        result.to_json
      elsif params[:back]
        if result[0] == "ok"
          flash :notice, "Created message #{result[1]}"
        else
          flash :notice, "Error creating message: #{result[1]}"
        end
        redirect params[:back]
      else
        erb :new_message_post, :layout => true, :locals => { :result => result, :q_name => qc.name }
      end
    end

    post '/q/:name/adminoper' do
      res = if params[:pause] && params[:resume] && params[:down] && params[:up]
        # Makes no sense
      elsif params[:pause]
        action = "pause"
        queuemgr.pause_queue(params[:name])
      elsif params[:resume]
        action = "resume"
        queuemgr.resume_queue(params[:name])
      elsif params[:down]
        action = "down"
        queuemgr.down_queue(params[:name])
      elsif params[:up]
        action = "up"
        queuemgr.up_queue(params[:name])
      end

      if not res
        throw :halt, [500, "500 - Couldn't #{action} queue. Internal error."]
      end
      if res[0] != 'ok'
        throw :halt, [500, "500 - Couldn't #{action} queue. #{res.inspect}."]
      end

      flash :notice, "Successfully #{action}d queue #{params[:name]}"
      redirect params[:back]
    end

    post '/q/:name/restart' do
      res = queuemgr.restart_queue(params[:name])

      if not res
        throw :halt, [500, "500 - Couldn't restart queue. Internal error."]
      end
      if res[0] != 'ok'
        throw :halt, [500, "500 - Couldn't restart queue. #{res.inspect}."]
      end

      flash :notice, "Successfully restarted queue #{params[:name]}"
      redirect params[:back]
    end

    get '/q/:name/config.json' do
      path = "./queue/#{params['name']}/config.json"

      if not File.exists? path
        throw :halt, [404, "404 - Queue config for '#{params['name']}' not found"]
      end

      send_file(path)
    end

    get '/q/:name/config' do
      begin
        qc = get_queueclient(params[:name])
      rescue RQ::RqQueueNotFound
        throw :halt, [404, "404 - Queue not found"]
      end

      ok, config = qc.config
      config.to_json
    end

    get '/q/:name/:msg_id' do
      fmt = :html
      msg_id = params['msg_id']

      extension = msg_id[-5..-1]
      if extension == '.json'
        fmt = :json
        msg_id = msg_id[0..-6]
      end

      begin
        qc = get_queueclient(params[:name])
      rescue RQ::RqQueueNotFound
        throw :halt, [404, "404 - Queue not found"]
      end

      ok, msg = qc.get_message({ 'msg_id' => msg_id })

      if ok != 'ok'
        throw :halt, [404, "404 - Message ID not found"]
      end

      if fmt == :html
        if msg['state'] == 'prep'
          erb :prep_message, :locals => { :q_name => qc.name, :msg_id => msg_id, :msg => msg }
        else
          erb :message, :locals => { :q_name => qc.name,  :msg_id => msg_id, :msg => msg }
        end
      else
        #content_type 'application/json'
        msg.to_json
      end
    end

    get '/q/:name/:msg_id/state.json' do
      fmt = :json
      msg_id = params['msg_id']

      begin
        qc = get_queueclient(params[:name])
      rescue RQ::RqQueueNotFound
        throw :halt, [404, "404 - Queue not found"]
      end

      ok, state = qc.get_message_state({ 'msg_id' => msg_id })

      if ok != 'ok'
        throw :halt, [404, "404 - Message ID not found"]
      end

      [ state ].to_json
    end


    post '/q/:name/:msg_id/clone' do
      begin
        qc = get_queueclient(params[:name])
      rescue RQ::RqQueueNotFound
        throw :halt, [404, "404 - Queue not found"]
      end

      res = qc.clone_message({ 'msg_id' => params[:msg_id] })

      if not res
        throw :halt, [500, "500 - Couldn't clone message. Internal error."]
      end
      if res[0] != 'ok'
        throw :halt, [500, "500 - Couldn't clone message. #{res.inspect}."]
      end

      flash :notice, "Message cloned successfully"
      redirect "#{root}q/#{params[:name]}"
    end

    post '/q/:name/:msg_id/run_now' do
      begin
        qc = get_queueclient(params[:name])
      rescue RQ::RqQueueNotFound
        throw :halt, [404, "404 - Queue not found"]
      end

      res = qc.run_message({ 'msg_id' => params[:msg_id] })

      if not res
        throw :halt, [500, "500 - Couldn't run message. Internal error."]
      end
      if res[0] != 'ok'
        throw :halt, [500, "500 - Couldn't run message. #{res.inspect}."]
      end

      flash :notice, "Message in run successfully"
      redirect "#{root}q/#{params[:name]}/#{params[:msg_id]}"
    end

    # TODO: change URL for this call
    post '/q/:name/:msg_id/attach/new' do
      begin
        qc = get_queueclient(params[:name])
      rescue RQ::RqQueueNotFound
        throw :halt, [404, "404 - Queue not found"]
      end

      # Sample of what params look like
      # {"name"=>"test", "filedata"=>{:type=>"image/jpeg", :head=>"Content-Disposition: form-data; name=\"data\"; filename=\"studio3.jpg\"\r\nContent-Type: image/jpeg\r\n", :tempfile=>#<File:/var/folders/st/st7hSqrMFB0Sfm3p4OeypE+++TM/-Tmp-/RackMultipart20091218-76387-t47zdi-0>, :name=>"filedata", :filename=>"studio3.jpg"}, "msg_id"=>"20091215.1829.21.853", "x_format"=>"json"}
      #
      #p params
      #p params['filedata']
      #p params['filedata'][:tempfile].path
      #p params['filedata'][:tempfile].class
      #p params['filedata'][:tempfile].methods.sort

      if not params['filedata']
        throw :halt, [404, "404 - Missing required param filedata"]
      end

      if params['filedata'].class != Hash
        throw :halt, [404, "404 - Wrong input type for filedata param"]
      end

      if not params['filedata'][:tempfile]
        throw :halt, [404, "404 - Missing pathname to upload temp file in filedata param"]
      end

      if not params['filedata'][:filename]
        throw :halt, [404, "404 - Missing filename of uploaded file in filedata param"]
      end


      api_call = params.fetch('x_format', 'html')

      msg = { 'msg_id' => params['msg_id'],
        'pathname' => params['filedata'][:tempfile].path,
        'name' => params['filedata'][:filename]
      }

      result = qc.attach_message( msg )

      # Success - clean up temp file
      if result[0] == "ok"
        File.unlink(params['filedata'][:tempfile].path) rescue nil
      end

      if api_call == 'json'
        result.to_json
      else
        if result[0] == "ok"
          flash :notice, "Attached message successfully"
          redirect "#{root}q/#{params[:name]}/#{params[:msg_id]}"
        else
          "Commit #{params[:name]}/#{params[:msg_id]} got #{result}"
        end
      end
    end

    post '/q/:name/:msg_id/attach/:attachment_name' do
      begin
        qc = get_queueclient(params[:name])
      rescue RQ::RqQueueNotFound
        throw :halt, [404, "404 - Queue not found"]
      end

      api_call = params.fetch('x_format', 'html')

      result = ['fail', 'unknown']
      if params[:_method] == 'delete'
        result = qc.delete_attach_message( {'msg_id' => params[:msg_id],
                                            'attachment_name' => params[:attachment_name]} )
        if api_call == 'json'
          result.to_json
        else
          if result[0] == "ok"
            flash :notice, "Attachment deleted successfully"
            redirect "#{root}q/#{params[:name]}/#{params[:msg_id]}"
          else
            "Delete of attach #{params[:attachment_name]} on #{params[:name]}/#{params[:msg_id]} got #{result}"
          end
        end
      else
        throw :halt, [400, "400 - Invalid method param"]
      end
    end

    get '/q/:name/:msg_id/log/:log_name' do
      begin
        qc = get_queueclient(params[:name])
      rescue RQ::RqQueueNotFound
        throw :halt, [404, "404 - Queue not found"]
      end

      msg_id = params['msg_id']
      ok, msg = qc.get_message({ 'msg_id' => msg_id })

      if ok != 'ok'
        throw :halt, [404, "404 - Message ID not found"]
      end

      path = "#{msg['path']}/job/#{params['log_name']}"

      # send_file does this check, but we provide a much more contextually relevant error
      # TODO: finer grained checking (que, msg_id exists, etc.)
      if not File.exists? path
        throw :halt, [404, "404 - Message ID log '#{params['log_name']}' not found"]
      end

      send_file(path)
    end

    get '/q/:name/:msg_id/attach/:attach_name' do
      begin
        qc = get_queueclient(params[:name])
      rescue RQ::RqQueueNotFound
        throw :halt, [404, "404 - Queue not found"]
      end

      msg_id = params['msg_id']
      ok, msg = qc.get_message({ 'msg_id' => msg_id })

      if ok != 'ok'
        throw :halt, [404, "404 - Message ID not found"]
      end

      path = "#{msg['path']}/attach/#{params['attach_name']}"

      # send_file does this check, but we provide a much more contextually relevant error
      # TODO: finer grained checking (que, msg_id exists, etc.)
      if not File.exists? path
        throw :halt, [404, "404 - Message ID attachment '#{params['attach_name']}' not found"]
      end

      send_file(path)
    end

    get '/q/:name/:msg_id/tailview/:attach_name' do
      begin
        qc = get_queueclient(params[:name])
      rescue RQ::RqQueueNotFound
        throw :halt, [404, "404 - Queue not found"]
      end

      msg_id = params['msg_id']
      ok, msg = qc.get_message({ 'msg_id' => msg_id })

      if ok != 'ok'
        throw :halt, [404, "404 - Message ID not found"]
      end

      path = "#{msg['path']}/attach/#{params['attach_name']}"

      # send_file does this check, but we provide a much more contextually relevant error
      # TODO: finer grained checking (que, msg_id exists, etc.)
      if not File.exists? path
        throw :halt, [404, "404 - Message ID attachment '#{params['attach_name']}' not found"]
      end

      erb :tailview, :layout => false,
                     :locals => {
                       :tail_path  => path,
                       :state_path => "#{root}q/#{params[:name]}/#{msg_id}/state.json",
                       :name       => params['attach_name'],
                     }
    end

    get '/q/:name/:msg_id/tailviewlog/:log_name' do
      begin
        qc = get_queueclient(params[:name])
      rescue RQ::RqQueueNotFound
        throw :halt, [404, "404 - Queue not found"]
      end

      msg_id = params['msg_id']
      ok, msg = qc.get_message({ 'msg_id' => msg_id })

      if ok != 'ok'
        throw :halt, [404, "404 - Message ID not found"]
      end

      erb :tailview, :layout => false,
                     :locals => {
                       :tail_path  => "#{root}q/#{params[:name]}/#{msg_id}/log/#{params[:log_name]}",
                       :state_path => "#{root}q/#{params[:name]}/#{msg_id}/state.json",
                     }
    end


    post '/q/:name/:msg_id' do
      begin
        qc = get_queueclient(params[:name])
      rescue RQ::RqQueueNotFound
        throw :halt, [404, "404 - Queue not found"]
      end

      api_call = params.fetch('x_format', 'html')

      case params[:_method]
      when 'delete'
        result = qc.delete_message( {'msg_id' => params[:msg_id]} )
        if api_call == 'json'
          result.to_json
        else
          if result[0] == "ok"
            flash :notice, "Message deleted successfully"
            redirect "#{root}q/#{params[:name]}"
          else
            flash :error, "Delete got #{result.inspect}"
            redirect "#{root}q/#{params[:name]}/#{params[:msg_id]}"
          end
        end

      when 'destroy'
        result = qc.destroy_message( {'msg_id' => params[:msg_id]} )
        if api_call == 'json'
          result.to_json
        else
          if result[0] == "ok"
            flash :notice, "Message destroyed successfully"
            redirect "#{root}q/#{params[:name]}"
          else
            flash :error, "destroy got #{result.inspect}"
            redirect "#{root}q/#{params[:name]}/#{params[:msg_id]}"
          end
        end

      when 'commit'
        result = qc.commit_message( {'msg_id' => params[:msg_id]} )
        if api_call == 'json'
          result.to_json
        else
          if result[0] == "ok"
            flash :notice, "Message committed successfully"
          else
            flash :error, "Commit got #{result.inspect}"
          end
          redirect "#{root}q/#{params[:name]}/#{params[:msg_id]}"
        end
      else
        throw :halt, [400, "400 - Invalid method param"]
      end
    end

  end
end
