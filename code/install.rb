

require 'sinatra/base'
require 'erb'

load 'code/queuemgrclient.rb'

#require 'sinatra'
#    set :root, File.dirname('code')
#set :root, File.dirname('code'__FILE__)

def start_backend
  `./bin/queuemgr_ctl start`
  p $?
  p "Kicked off process start..."
end


module RQ
  class Install < Sinatra::Base

    def self.views
      './code/views'
    end

    get '/install' do
      erb :install
    end

    post '/install' do
      FileUtils.mkdir('config')

      # After watching my mds process go nuts
      # http://support.apple.com/kb/TA24975?viewlocale=en_US
      FileUtils.mkdir('queue.noindex')
      FileUtils.ln_sf('queue.noindex', 'queue')
      p "Starting..."
      # This isn't working in WEBrick
      start_backend
      p "Started..."

      # Wait for sock file
      i = 0
      while not File.exist? 'config/queuemgr.sock'
        i = i + 1
        sleep 0.10
      end

      queue = {}
      queue['url'] = "http://localhost:#{request.port}/"
      queue['name'] = "relay"
      queue['script'] = "./code/relay_script.rb"
      queue['ordering'] = "ordered"
      queue['num_workers'] = "1"
      queue['fsync'] = 'fsync'
      result = RQ::QueueMgrClient.create_queue(queue)

      queue = {}
      queue['url'] = "http://localhost:#{request.port}/"
      queue['name'] = "webhook"
      queue['script'] = "./code/webhook_script.rb"
      queue['ordering'] = "ordered"
      queue['num_workers'] = "1"
      queue['fsync'] = 'fsync'
      result = RQ::QueueMgrClient.create_queue(queue)
      # TODO: set install state as bad if any of this fails

      erb :installed
    end
  end
end
