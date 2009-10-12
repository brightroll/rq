

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
      # Create a queue
      # Start a queue
      result = RQ::QueueMgrClient.create_queue(params['queue'])
      "We got <pre> #{params.inspect} </pre> from form, and #{result} from QueueMgr"
    end
  end
end
