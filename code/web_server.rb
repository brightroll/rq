require 'unixrack'
require 'fileutils'
require 'json'
require 'code/router'

module RQ
  class WebServer

    def initialize(config)
      @basic_auth  = config['basic_auth']
      @port        = config['port']
      @addr        = config['addr']
      @host        = config['host']
      @allowed_ips = config['allowed_ips']
    end

    def run!
      minirouter = MiniRouter.new
      router = minirouter

      if @basic_auth
        protected_router = Rack::Auth::Basic.new(minirouter) do |username, password|
          @basic_auth['users'][username] == password
        end
        protected_router.realm = @basic_auth['realm']
        router = protected_router
      end

      Rack::Handler::UnixRack.run(router, {
        :Port        => @port,
        :Host        => @addr,
        :Hostname    => @host,
        :allowed_ips => @allowed_ips,
      })
    end
  end
end
