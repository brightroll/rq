

require 'sinatra/base'
require 'erb'

#require 'sinatra'
#    set :root, File.dirname('code')
#set :root, File.dirname('code'__FILE__)

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
      `ruby ./code/queuemgr_ctl.rb run`
      erb :installed
    end
  end
end
