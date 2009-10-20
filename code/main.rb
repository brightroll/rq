

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

      if this_queue == params['mesg']['dest']
        q_name = params[:name]
      else
        if params['mesg']['relay_ok'] == 'yes'
          q_name = 'relay' # Relay is the special Q
        else
          throw :halt, [404, "404 - Not this Queue. Relaying not allowed"]
        end
      end

      qc = RQ::QueueClient.new(q_name)

      if not qc.exists?
        throw :halt, [404, "404 - Queue not found"]
      end

      result = qc.create_message(params['mesg'])
      "We got <pre> #{params.inspect} </pre> from form, and #{result} from Queue #{q_name}"
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
