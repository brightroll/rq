

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
      FileUtils.mkdir('queue')
      `ruby ./code/queuemgr_ctl.rb run`
      erb :installed
    end
  end
end
