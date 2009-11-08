

require 'sinatra/base'
require 'erb'

#require 'sinatra'
#    set :root, File.dirname('code')
#set :root, File.dirname('code'__FILE__)

def start_backend
  fork do
    exec "ruby ./code/queuemgr_ctl.rb start"
  end
  p "Waiting on start..."
  Process.wait
  p "Done Waiting..."
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
      #start_backend
      p "Started..."
      erb :installed
    end
  end
end
