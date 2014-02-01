require 'vendor/environment'
require 'unixrack'
require 'fileutils'
require 'json'
require 'code/router'

module RQ
  class WebServer
    def initialize(config)
      @config = config
    end

    def run!
      minirouter = MiniRouter.new
      router = minirouter

      if @config['basic_auth']
        protected_router = Rack::Auth::Basic.new(minirouter) do |username, password|
          @config['basic_auth']['users'][username] == password
        end
        protected_router.realm = @config['basic_auth']['realm']
        router = protected_router
      end

      Rack::Handler::UnixRack.run(router, {
        :Port        => @config['port'],
        :Hostname    => @config['host'],
        :allowed_ips => @config['allowed_ips'],
        :Host        => @config['addr'],
      })
    end
  end
end
