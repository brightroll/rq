

require 'sinatra/base'
require 'erb'
load 'code/queuemgrclient.rb'
load 'code/queueclient.rb'

module RQ
  class Main < Sinatra::Base
    def self.views
      './code/views'
    end

    helpers do
      def url
        "http://#{request.host}:#{request.port}/"
      end
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
      "We got <pre> #{params.inspect} </pre> from form, and #{result} from QueueMgr"
    end

    get '/q.txt' do
      content_type 'text/plain', :charset => 'utf-8'
      erb :queue_list, :layout => false, :locals => {:queues => RQ::QueueMgrClient.queues}
    end
    
    get '/q/:name' do
      if params[:name].index(".txt")
        content_type 'text/plain', :charset => 'utf-8'
        return erb :queue_txt, :layout => false, :locals => { :qc => RQ::QueueClient.new(params[:name].split(".txt").first) }
      end

      # check for queue
      # TODO: sanitize names (no dots or slashes)
      qc = RQ::QueueClient.new(params[:name])

      if not qc.exists?
        throw :halt, [404, "404 - Queue not found"]
      end

      erb :queue
    end

    get '/q/:name/new_message' do
      # check for queue
      # TODO: sanitize names (no dots or slashes)
      qc = RQ::QueueClient.new(params[:name])

      if not qc.exists?
        throw :halt, [404, "404 - Queue not found"]
      end

      erb :new_message
    end

    post '/q/:name/new_message' do
      # check for queue
      this_queue = "http://#{request.host}:#{request.port}/q/#{params[:name]}"

      api_call = params.fetch('x_format', 'html')
      if api_call == 'json'
        prms = JSON.parse(params['mesg'])
      else
        prms = params['mesg']
      end

      if this_queue == prms['dest']
        q_name = params[:name]
      else
        if prms['relay_ok'] == 'yes'
          q_name = 'relay' # Relay is the special Q
        else
          throw :halt, [404, "404 - Not this Queue. Relaying not allowed"]
        end
      end

      qc = RQ::QueueClient.new(q_name)

      if not qc.exists?
        throw :halt, [404, "404 - Queue not found"]
      end

      if prms.fetch("_method", 'commit') == 'prep'
        result = qc.prep_message(prms)
      else
        result = qc.create_message(prms)
      end

      if api_call == 'json'
        "#{result.to_json}"
      else
        "We got <pre> #{prms.inspect} </pre> from form, and #{result} from Queue #{q_name}"
      end
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

      qc = RQ::QueueClient.new(params[:name])

      if not qc.exists?
        throw :halt, [404, "404 - Queue not found"]
      end

      ok, msg = qc.get_message({ 'msg_id' => msg_id })

      if ok != 'ok'
        throw :halt, [404, "404 - Message ID not found"]
      end

      if fmt == :html
        erb :message, { :locals => { 'msg_id' => msg_id, 'msg' => msg } }
      else
        #content_type 'application/json'
        msg.to_json
      end
    end

    post '/q/:name/:msg_id/attach/new' do
      # check for queue
      # TODO: sanitize names (no dots or slashes)
      qc = RQ::QueueClient.new(params[:name])

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

      if api_call == 'json'
        result.to_json
      else
        "Commit #{params[:name]}/#{params[:msg_id]} got #{result}"
      end
    end

    get '/q/:name/:msg_id/:attach_name' do

      path = "./queue/#{params['name']}/done/#{params['msg_id']}/attach/#{params['attach_name']}"

      # send_file does this check, but we provide a much more contextually relevant error
      # TODO: finer grained checking (que, msg_id exists, etc.)
      if not File.exists? path
        throw :halt, [404, "404 - Message ID attachment '#{params['attach_name']}' not found"]
      end

      send_file(path)
    end

    post '/q/:name/:msg_id' do
      # check for queue
      # TODO: sanitize names (no dots or slashes)
      qc = RQ::QueueClient.new(params[:name])

      if not qc.exists?
        throw :halt, [404, "404 - Queue not found"]
      end

      api_call = params.fetch('x_format', 'html')

      if params[:_method] == 'delete'
        result = qc.delete_message( {'msg_id' => params[:msg_id]} )
        "Delete #{params[:name]}/#{params[:msg_id]} got #{result}"
      elsif params[:_method] == 'commit'
        result = qc.commit_message( {'msg_id' => params[:msg_id]} )
        if api_call == 'json'
          result.to_json
        else
          "Commit #{params[:name]}/#{params[:msg_id]} got #{result}"
        end
      else
        "Post #{params[:name]}/#{params[:msg_id]}"
      end
    end

    get '/q/:name/restart' do
      qc = RQ::QueueClient.new(params[:name])

      if not qc.exists?
        throw :halt, [404, "404 - Queue not found"]
      end

      qc.shutdown

      <<-HERE
        <script type="text/javascript">
        <!--
        function delayer(){
            history.back();
        }
        setTimeout('delayer()', 1000);
        //-->
        </script>
        Queue restarted... (returning in 1 sec)
      HERE
    end

  end
end
