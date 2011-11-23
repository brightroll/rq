

require 'sinatra/base'
require 'erb'

load 'code/queuemgrclient.rb'

require 'json'

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

    before do
      @flash = session[:flash] || {}
      session[:flash] = {}
    end

    def write_file(fname, data)
      File.open(fname + ".tmp", "w") do |f|
        f.write(data)
      end
      File.rename(fname + ".tmp", fname)
    end

    get '/install' do
      erb :install
    end

    post '/install' do
      if File.exists? 'config'
        return "Already installed"
      end
      FileUtils.mkdir('config')

      # Setup the network config file

      # TODO: do error/sanity checking

      # Clean up any whitespace
      prms = params['install'].keys.inject({}) do |acc, k|
        acc[k] = params['install'][k].strip
        acc
      end

      write_file("config/config.json", prms.to_json)

      # After watching my mds process go nuts
      # http://support.apple.com/kb/TA24975?viewlocale=en_US
      FileUtils.mkdir('queue.noindex')
      FileUtils.ln_sf('queue.noindex', 'queue')
      FileUtils.mkdir('scheduler')
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
      queue['name'] = "relay"
      queue['script'] = "./code/relay_script.rb"
      queue['ordering'] = "none"
      queue['num_workers'] = "1"
      queue['fsync'] = 'no-fsync'
      result = RQ::QueueMgrClient.create_queue(queue)

      queue = {}
      queue['name'] = "webhook"
      queue['script'] = "./code/webhook_script.rb"
      queue['ordering'] = "none"
      queue['num_workers'] = "1"
      queue['fsync'] = 'no-fsync'
      result = RQ::QueueMgrClient.create_queue(queue)

      queue = {}
      queue['name'] = "cleaner"
      queue['script'] = "./code/cleaner_script.rb"
      queue['ordering'] = "none"
      queue['num_workers'] = "1"
      queue['fsync'] = 'no-fsync'
      result = RQ::QueueMgrClient.create_queue(queue)

      queue = {}
      queue['name'] = "rq_router"
      queue['script'] = "./code/rq_router_script.rb"
      queue['ordering'] = "none"
      queue['num_workers'] = "1"
      queue['fsync'] = 'no-fsync'
      result = RQ::QueueMgrClient.create_queue(queue)

      # TODO: set install state as bad if any of this fails

      erb :installed
    end
  end
end
