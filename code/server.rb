
Dir.glob(File.join("code", "vendor", "gems", "*", "lib")).each do |lib|
  $LOAD_PATH.unshift(File.expand_path(lib))
end

require 'rubygems'
gem_paths = [File.expand_path(File.join("code", "vendor", "gems")),  Gem.default_dir]
Gem.clear_paths
Gem.send :set_paths, gem_paths.join(":")

 
require 'rack'
 
# fastcgi_log = File.open("fastcgi.log", "a")
# STDOUT.reopen fastcgi_log
# STDERR.reopen fastcgi_log
# STDOUT.sync = true

# module Rack
#   class Request
#     def path_info
#       @env["REDIRECT_URL"].to_s
#     end
#     def path_info=(s)
#       @env["REDIRECT_URL"] = s.to_s
#     end
#   end
# end

class MiniRouter

  def call(env)
    path = env["PATH_INFO"].to_s.squeeze("/")
    p "PATH: #{path}"
    if path.index('/css') or path.index('/javascripts') or path.index('/favicon.ico')
      load 'code/main.rb'
      return Rack::Static.new(nil, :urls => ["/css", "/javascripts", "/favicon.ico"], :root => 'code/public').call(env)
    end
    if path == '/install'
      load 'code/install.rb'
      return RQ::Install.new.call(env)
    end
    if not File.exists?('config')
      resp = Rack::Response.new()
      resp.redirect('/install')
      return resp.finish
    end
    if true #path == '/'
      load 'code/main.rb'
      #return Rack::Static.new(RQ::Main.new, :urls => ["/css", "/javascripts"], :root => 'code/public').call(env)
      return RQ::Main.new.call(env)
    end
  end
end


     
#Dir.chdir('code')

#use Rack::ShowExceptions
#use Rack::Static, :urls => ["/css", "/javascripts"], :root => 'code/public'

builder = MiniRouter.new
#builder = Rack::Builder.new do
#  use Rack::ShowExceptions
#  use Rack::Static, :urls => ["/css", "/javascripts"], :root => 'code/public'
#
#  map '/' do
#    load 'code/install.rb'
#    load 'code/main.rb'
#    p 'DRUDRUDURDUDRUDRURUR'
#    p Dir.pwd
#    p 'DRUDRUDURDUDRUDRURUR'
#    if not File.exists?('config')
#      run Redirect.new('/install')
#    else
#      run RQ::Main.new
#    end
#  end
#
#  map '/install' do
#    load 'code/install.rb'
#    run RQ::Install.new
#  end
#end

# Rack::Handler::FastCGI.run(builder)
Rack::Handler::WEBrick.run(builder, :Port => 3333)
#run builder
