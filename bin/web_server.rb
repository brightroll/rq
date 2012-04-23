#!/usr/bin/ruby

Dir.chdir(File.join(File.dirname(__FILE__), ".."))

require 'vendor/environment.rb'
require 'code/unixrack.rb'
require 'code/router.rb'
require 'json'
require 'fileutils'


def run(daemon = false)
  Signal.trap('HUP', 'IGNORE') # Don't die upon logout
  FileUtils.mkdir_p("log")

  exit(1) unless File.directory?("log")

  if daemon
    STDIN.reopen("/dev/null")
    STDOUT.reopen("log/web_server.log", "a")
    STDOUT.sync = true
    $stderr = STDOUT
  end

  Signal.trap("TERM") do 
    puts "Got term... doing kill"
    Process.kill("KILL", Process.pid)
  end

  minirouter = MiniRouter.new
  router = minirouter

  if $basic_auth
    protected_router = Rack::Auth::Basic.new(minirouter) do |username, password|
      $basic_auth['users'][username] == password
    end
    protected_router.realm = $basic_auth['realm']
    router = protected_router
  end

  Rack::Handler::UnixRack.run(router, {:Port => $port,
                                       :Hostname => $host,
                                       :allowed_ips => $allowed_ips,
                                       :Host => $addr})
end


#
# HANDLE CONFIG

if ARGV[0] == "install"
  $host = "127.0.0.1"
  $port = "3333"
  $addr = "0.0.0.0"
  $allowed_ips = []
  $basic_auth = nil
else
  begin
    data = File.read('config/config.json')
    config = JSON.parse(data)
    $host = config['host']
    $port = config['port']
    $addr = config['addr']
    $allowed_ips = config['allowed_ips'] || []
    $basic_auth = config['basic_auth']
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
  rescue
    puts "Couldn't read config/config.json file properly. Exiting"
    exit! 1
  end
end


#
# HANDLE ARGV

if ARGV[0] == "server"
  puts "Starting in background..."
  pid = fork
  if pid
    Process.detach(pid)
  else
    run(true)
  end
else
  puts "Staying in foreground..."
  run()
end

