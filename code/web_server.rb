require 'vendor/environment'
require 'unixrack'
require 'fileutils'
require 'json'
require 'code/router'
require 'version'

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

    def self.load_config(conffile = 'config/config.json')
      ENV["RQ_VER"] = VERSION_NUMBER
      ENV["RQ_SEMVER"] = SEMANTIC_VERSION_NUMBER

      begin
        config = JSON.parse(File.read(conffile))
        ENV['RQ_ENV'] = 'development' || config['env']
        config = config.merge('host' => config['host'], 'port' => config['port'])
        set_tmp_dir(config['tmpdir'])
      rescue Exception => e
        puts "Couldn't read config/config.json file properly. Exiting"
        puts e.message.inspect
        puts e.backtrace.join('\n')
        exit! 1
      end
      config
    end

    def set_tmp_dir(location)
      dir = File.expand_path(location)
      if File.directory?(dir) && File.writable?(dir)
        ENV['TMPDIR'] = dir
      else
        puts "Bad 'tmpdir' in config json [#{dir}]. Exiting"
        exit! 1
      end
    end
  end
end
