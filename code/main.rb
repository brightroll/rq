

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

    get '/q/:name' do
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

      result = qc.create_message(prms)

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

    post '/q/:name/:msg_id' do
      # check for queue
      # TODO: sanitize names (no dots or slashes)
      qc = RQ::QueueClient.new(params[:name])

      if not qc.exists?
        throw :halt, [404, "404 - Queue not found"]
      end

      if params[:_method] == 'delete'
        result = qc.delete_message( {'msg_id' => params[:msg_id]} )
        "Delete #{params[:name]}/#{params[:msg_id]} got #{result}"
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
