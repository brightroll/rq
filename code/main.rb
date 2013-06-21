require 'sinatra/base'
require 'erb'

require 'code/queuemgrclient'
require 'code/queueclient'
require 'code/hashdir'
require 'code/portaproc'
require 'code/overrides'

module RQ
  class Main < Sinatra::Base

    disable :protection
    enable :sessions
    set :session_secret, 'super secret'  # we are forking, so we must set
    set :erb, :trim => '-'

    def self.views
      './code/views'
    end

    helpers do
      def url
        "http://#{request.host}:#{request.port}/"
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

      def queue_row(name, options={})
        qc = get_queueclient(name)
        html = options[:odd] ?
             "<tr class=\"odd-row\">" :
             "<tr>"
        html += "<td class=\"left-aligned\"><a href=\"#{url}q/#{name}\">#{name}</a></td>"
        html += "<td class=\"left-aligned\"><a href=\"#{url}q/#{name}\">#{(url+'q/'+name.to_s)}</a></td>"
        if qc.running?
          admin_stat, oper_stat = qc.status
          html += "<td>"
            html += "<span class=\"#{admin_stat == 'UP' ? 'green' : 'red'}\">#{admin_stat}</span>:"
            html += "<span class=\"#{oper_stat  == 'UP' ? 'green' : 'red'}\">#{oper_stat}</span>"
          html += "</td>"
          html += "<td>#{qc.ping}</td>"
          html += "<td>#{qc.read_pid}</td>"
          html += "<td>#{qc.uptime}</td>"
        else
          html +=
          html += "<td><span class=\"red\">DOWN</span></td>"
          html += "<td>-</td>"
          html += "<td>-</td>"
          html += "<td>-</td>"
        end
        html += "<td><form method=\"post\" action=\"#{url}q/#{name}/restart\">"
          html += "<button id=\"restart-queue\">Restart</button>"
        html += "</form></td>"
        html += "</tr>"
      end

      def flash(type, msg)
        h = session[:flash] || {}
        h[type] = msg
        session[:flash] = h
      end

      def flash_now(type, msg)
        h = @flash || {}
        h[type] = msg
        @flash = h
      end
    end

    before do
      val = session[:flash]
      @flash = val || {}
      session[:flash] = {}
    end

    # handle 404s
    not_found do
      flash_now :error, "404 -- No route matches #{request.path_info}"
      erb :main
    end

    get '/' do
      erb :main
    end

    get '/new_queue' do
      erb :new_queue
    end

    post '/new_queue' do
      # TODO: validation

      # This creates and starts a queue
      result = RQ::QueueMgrClient.create_queue(params['queue'])
      flash :notice, "We got <code>#{params.inspect}</code> from form, and <code>#{result}</code> from QueueMgr"
      redirect "/q/#{params['queue']['name']}"
    end

    post '/new_queue_link' do
      # This creates and starts a queue via a config file in json
      js_data = {}
      begin
        js_data = JSON.parse(File.read(params['queue']['json_path']))
      rescue
        p $!
        p "BAD config.json - could not parse"
        throw :halt, [404, "404 - Couldn't parse json file (#{params['queue']['json_path']})."]
        end
      result = RQ::QueueMgrClient.create_queue_link(params['queue']['json_path'])
      #TODO - do the right thing with the result code
      flash :notice, "We got <code>#{params.inspect}</code> from form, and <code>#{result}</code> from QueueMgr"
      redirect "/q/#{js_data['name']}"
    end

    post '/delete_queue' do
      # This creates and starts a queue
      result = RQ::QueueMgrClient.delete_queue(params['queue_name'])
      flash :notice, "We got <code>#{params.inspect}</code> from form, and <code>#{result}</code> from QueueMgr"
      redirect "/"
    end

    get '/q.txt' do
      content_type 'text/plain', :charset => 'utf-8'
      erb :queue_list, :layout => false, :locals => {:queues => RQ::QueueMgrClient.queues}
    end

    get '/q.json' do
      RQ::QueueMgrClient.queues.to_json
    end

    get '/proc.txt' do
      content_type 'text/plain', :charset => 'utf-8'
      ps = RQ::PortaProc.new
      ok, procs = ps.get_list
      if not ok
        throw :halt, [503, "503 - Could not get process list"]
      end
      erb :proc_list, :layout => false, :locals => {:queues => RQ::QueueMgrClient.queues, :procs => procs}, :trim => '-'
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

      if not RQ::QueueMgrClient.running?
        throw :halt, [503, "503 - QueueMgr not running"]
      end

      # check for queue
      # TODO: sanitize names (no dots or slashes)
      qc = RQ::QueueClient.new(params[:name])

      throw :halt, [404, "404 - Queue not found"] unless qc.exists?

      erb :queue
    end

    get '/q/:name/done.json' do
      if not RQ::QueueMgrClient.running?
        throw :halt, [503, "503 - QueueMgr not running"]
      end

      qc = RQ::QueueClient.new(params[:name])
      throw :halt, [404, "404 - Queue not found"] unless qc.exists?

      limit = 10
      if params['limit']
        limit = params['limit'].to_i
      end
      result = qc.messages({'state' => 'done', 'limit' => limit})
      "#{result.to_json}"
    end

    get '/q/:name/new_message' do
      # check for queue
      # TODO: sanitize names (no dots or slashes)
      qc = get_queueclient(params[:name])

      throw :halt, [404, "404 - Queue not found"] unless qc.exists?

      overrides = RQ::Overrides.new(params['name'])
      erb :new_message, :layout => true, :locals => {:o => overrides }
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

      the_method = prms.fetch("_method", 'commit')

      # request.host and request.port are setup by the config file
      hostnames = [ "http://#{request.host}:#{request.port}/" ]
      if File.exists? "./config/aliases.json"
        begin
          js_data = JSON.parse(File.read("./config/aliases.json"))
          hostnames.concat(js_data['hostnames'] || [])
        rescue
          p $!
          p "BAD aliases.json - could not parse"
          throw :halt, [404, "404 - Couldn't parse existing aliases.json file."]
        end
      end

      if hostnames.any? {|h| prms['dest'].index(h) == 0}
        q_name = params[:name]
      else
        if (prms['relay_ok'] == 'yes') && (the_method != 'single_que')
          q_name = 'relay' # Relay is the special Q
        else
          throw :halt, [404, "404 - Not this Queue. Relaying not allowed"]
        end
      end

      qc = get_queueclient(q_name)

      throw :halt, [404, "404 - Queue not found"] unless qc.exists?

      if the_method == 'prep'
        result = qc.prep_message(prms)
      elsif the_method == 'single_que'
        result = qc.single_que(prms)
      elsif the_method == 'commit'
        result = qc.create_message(prms)
      else
        throw :halt, [400, "400 - Invalid method param"]
      end

      if result == [ "fail", "oper_status: DOWN"]
        throw :halt, [503, "503 - Service Unavailable - Operationally Down"]
      end

      if api_call == 'json'
        "#{result.to_json}"
      else
        erb :new_message_post, :layout => true, :locals => {:result => result, :q_name => q_name }
      end
    end

    post '/q/:name/restart' do
      res = RQ::QueueMgrClient.restart_queue(params[:name])

      if not res
        throw :halt, [500, "500 - Couldn't restart queue. Internal error."]
      end
      if res[0] != 'ok'
        throw :halt, [500, "500 - Couldn't restart queue. #{res.inspect}."]
      end

      flash :notice, "Successfully restarted queue #{params[:name]}"
      redirect back
    end

    get '/q/:name/config.json' do
      path = "./queue/#{params['name']}/config.json"

      if not File.exists? path
        throw :halt, [404, "404 - Queue config for '#{params['name']}' not found"]
      end

      send_file(path)
    end

    get '/q/:name/config' do
      qc = get_queueclient(params[:name])
      ok, config = qc.get_config()
      config.to_json
    end

    get '/q/:name/:msg_id' do
      # check for queue
      # TODO: sanitize names (no dots or slashes)

      fmt = :html
      msg_id = params['msg_id']

      extension = msg_id[-5..-1]
      if extension == '.json'
        fmt = :json
        msg_id = msg_id[0..-6]
      end

      qc = get_queueclient(params[:name])

      throw :halt, [404, "404 - Queue not found"] unless qc.exists?

      ok, msg = qc.get_message({ 'msg_id' => msg_id })

      if ok != 'ok'
        throw :halt, [404, "404 - Message ID not found"]
      end

      if fmt == :html
        if msg['state'] == 'prep'
          erb :prep_message, { :locals => { 'msg_id' => msg_id, 'msg' => msg } }
        else
          erb :message, { :locals => { 'msg_id' => msg_id, 'msg' => msg } }
        end
      else
        #content_type 'application/json'
        msg.to_json
      end
    end

    get '/q/:name/:msg_id/state.json' do
      fmt = :json
      msg_id = params['msg_id']

      qc = get_queueclient(params[:name])

      throw :halt, [404, "404 - Queue not found"] unless qc.exists?

      ok, state = qc.get_message_state({ 'msg_id' => msg_id })

      if ok != 'ok'
        throw :halt, [404, "404 - Message ID not found"]
      end

      [ state ].to_json
    end


    post '/q/:name/:msg_id/clone' do
      qc = get_queueclient(params[:name])
      throw :halt, [404, "404 - Queue not found"] unless qc.exists?
      res = qc.clone_message({ 'msg_id' => params[:msg_id] })

      if not res
        throw :halt, [500, "500 - Couldn't clone message. Internal error."]
      end
      if res[0] != 'ok'
        throw :halt, [500, "500 - Couldn't clone message. #{res.inspect}."]
      end

      flash :notice, "Message cloned successfully"
      redirect "/q/#{params[:name]}"
    end

    post '/q/:name/:msg_id/run_now' do
      qc = get_queueclient(params[:name])
      throw :halt, [404, "404 - Queue not found"] unless qc.exists?

      res = qc.run_message({ 'msg_id' => params[:msg_id] })

      if not res
        throw :halt, [500, "500 - Couldn't run message. Internal error."]
      end
      if res[0] != 'ok'
        throw :halt, [500, "500 - Couldn't run message. #{res.inspect}."]
      end

      flash :notice, "Message in run successfully"
      redirect "/q/#{params[:name]}/#{params[:msg_id]}"
    end

    post '/q/:name/:msg_id/attach/new' do
      # TODO: change URL for this call
      # check for queue
      # TODO: sanitize names (no dots or slashes)
      qc = get_queueclient(params[:name])

      if not qc.exists?
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
          redirect "/q/#{params[:name]}/#{params[:msg_id]}"
        else
          "Commit #{params[:name]}/#{params[:msg_id]} got #{result}"
        end
      end
    end

    post '/q/:name/:msg_id/attach/:attachment_name' do
      qc = get_queueclient(params[:name])

      if not qc.exists?
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
            redirect "/q/#{params[:name]}/#{params[:msg_id]}"
          else
            "Delete of attach #{params[:attachment_name]} on #{params[:name]}/#{params[:msg_id]} got #{result}"
          end
        end
      else
        throw :halt, [400, "400 - Invalid method param"]
      end
    end

    get '/q/:name/:msg_id/log/:log_name' do

      msg_id = params['msg_id']

      qc = get_queueclient(params[:name])

      if not qc.exists?
        throw :halt, [404, "404 - Queue not found"]
      end

      ok, msg = qc.get_message({ 'msg_id' => msg_id })

      if ok != 'ok'
        throw :halt, [404, "404 - Message ID not found"]
      end

      if ['done', 'relayed'].include? msg['state']
        path = RQ::HashDir.path_for("./queue/#{params['name']}/#{msg['state']}", params['msg_id'])
        path += "/job/#{params['log_name']}"
      else
        path = "./queue/#{params['name']}/#{msg['state']}/#{params['msg_id']}/job/#{params['log_name']}"
      end

      # send_file does this check, but we provide a much more contextually relevant error
      # TODO: finer grained checking (que, msg_id exists, etc.)
      if not File.exists? path
        throw :halt, [404, "404 - Message ID log '#{params['log_name']}' not found"]
      end

      send_file(path)
    end

    get '/q/:name/:msg_id/attach/:attach_name' do

      msg_id = params['msg_id']

      qc = get_queueclient(params[:name])

      if not qc.exists?
        throw :halt, [404, "404 - Queue not found"]
      end

      ok, msg = qc.get_message({ 'msg_id' => msg_id })

      if ok != 'ok'
        throw :halt, [404, "404 - Message ID not found"]
      end

      # TODO: use path from get_message instead of below
      if ['done', 'relayed'].include? msg['state']
        path = RQ::HashDir.path_for("./queue/#{params['name']}/#{msg['state']}", params['msg_id'])
        path += "/attach/#{params['attach_name']}"
      else
        path = "./queue/#{params['name']}/#{msg['state']}/#{params['msg_id']}/attach/#{params['attach_name']}"
      end

      # send_file does this check, but we provide a much more contextually relevant error
      # TODO: finer grained checking (que, msg_id exists, etc.)
      if not File.exists? path
        throw :halt, [404, "404 - Message ID attachment '#{params['attach_name']}' not found"]
      end

      send_file(path)
    end

    get '/q/:name/:msg_id/tailview/:attach_name' do

      msg_id = params['msg_id']

      qc = get_queueclient(params[:name])

      if not qc.exists?
        throw :halt, [404, "404 - Queue not found"]
      end

      ok, msg = qc.get_message({ 'msg_id' => msg_id })

      if ok != 'ok'
        throw :halt, [404, "404 - Message ID not found"]
      end

      # TODO: use path from get_message instead of below
      if ['done', 'relayed'].include? msg['state']
        path = RQ::HashDir.path_for("./queue/#{params['name']}/#{msg['state']}", params['msg_id'])
        path += "/attach/#{params['attach_name']}"
      else
        path = "./queue/#{params['name']}/#{msg['state']}/#{params['msg_id']}/attach/#{params['attach_name']}"
      end

      # send_file does this check, but we provide a much more contextually relevant error
      # TODO: finer grained checking (que, msg_id exists, etc.)
      if not File.exists? path
        throw :halt, [404, "404 - Message ID attachment '#{params['attach_name']}' not found"]
      end

      in_iframe = params['in_iframe'] == '1'

      erb :tailview, { :layout => false, :locals => { 'msg_id' => msg_id, 'msg' => msg, 'attach_name' => params['attach_name'], 'in_iframe' => in_iframe } }
    end

    get '/q/:name/:msg_id/tailviewlog/:log_name' do

      msg_id = params['msg_id']

      qc = get_queueclient(params[:name])

      if not qc.exists?
        throw :halt, [404, "404 - Queue not found"]
      end

      ok, msg = qc.get_message({ 'msg_id' => msg_id })

      if ok != 'ok'
        throw :halt, [404, "404 - Message ID not found"]
      end

      erb :tailview, {
                       :layout => false,
                       :locals => {
                         'path' => "/q/#{params[:name]}/#{msg_id}/log/#{params[:log_name]}",
                         'msg_path' => "/q/#{params[:name]}/#{msg_id}"
                       },
                     }
    end


    post '/q/:name/:msg_id' do
      # check for queue
      # TODO: sanitize names (no dots or slashes)
      qc = get_queueclient(params[:name])

      if not qc.exists?
        throw :halt, [404, "404 - Queue not found"]
      end

      api_call = params.fetch('x_format', 'html')

      if params[:_method] == 'delete'
        result = qc.delete_message( {'msg_id' => params[:msg_id]} )
        if api_call == 'json'
          result.to_json
        else
          if result[0] == "ok"
            flash :notice, "Message deleted successfully"
            redirect "/q/#{params[:name]}"
          else
            flash :error, "Delete got #{result.inspect}"
            redirect "/q/#{params[:name]}/#{params[:msg_id]}"
          end
        end
      elsif params[:_method] == 'commit'
        result = qc.commit_message( {'msg_id' => params[:msg_id]} )
        if api_call == 'json'
          result.to_json
        else
          if result[0] == "ok"
            flash :notice, "Message committed successfully"
          else
            flash :error, "Commit got #{result.inspect}"
          end
          redirect "/q/#{params[:name]}/#{params[:msg_id]}"
        end
      else
        throw :halt, [400, "400 - Invalid method param"]
      end
    end

  end
end
