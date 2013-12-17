require 'vendor/environment'
require 'unixrack'
require 'fileutils'
require 'json'
require 'code/router'

module RQ
  class WebServer
    def self.start_rq_web(config)
      FileUtils.mkdir_p("log")
      exit(1) unless File.directory?("log")

      minirouter = MiniRouter.new
      router = minirouter

      if config['basic_auth']
        protected_router = Rack::Auth::Basic.new(minirouter) do |username, password|
          config['basic_auth']['users'][username] == password
        end
        protected_router.realm = config['basic_auth']['realm']
        router = protected_router
      end

      Rack::Handler::UnixRack.run(router, {
        :Port        => config['port'],
        :Hostname    => config['host'],
        :allowed_ips => config['allowed_ips'],
        :Host        => config['addr'],
      })
    end

    def self.conf_rq_web(conffile = 'config/config.json')
      config = JSON.parse(File.read(conffile))
      if config['tmpdir']
        dir = File.expand_path(config['tmpdir'])
        if File.directory?(dir) and File.writable?(dir)
          # This will affect the class Tempfile, which is used by Rack
          ENV['TMPDIR'] = dir
        else
          puts "Bad 'tmpdir' in config json [#{dir}]. Exiting"
          exit! 1
        end
      end
      config
    rescue
      puts "Couldn't read config/config.json file properly. Exiting"
      exit! 1
    end
  end
end
