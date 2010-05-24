#!/usr/bin/ruby

Dir.chdir(File.join(File.dirname(__FILE__), ".."))

require 'vendor/environment.rb'
require 'code/unixrack.rb'
require 'code/router.rb'
require 'json'


def run
  Signal.trap('HUP', 'IGNORE') # Don't die upon logout
  FileUtils.mkdir_p("log")

  exit(1) unless File.directory?("log")

  STDIN.reopen("/dev/null")
  STDOUT.reopen("log/web_server.log", "a")
  #STDOUT.sync = true
  $stderr = STDOUT

  Signal.trap("TERM") do 
    Process.kill("KILL", Process.pid)
  end

  router = MiniRouter.new
  Rack::Handler::UnixRack.run(router, {:port => $port,
                                       :host => $host,
                                       :listen => $addr})
end


#
# HANDLE CONFIG

if ARGV[0] == "install"
  $host = "127.0.0.1"
  $port = "3333"
  $addr = "0.0.0.0"
else
  begin
    data = File.read('config/config.json')
    config = JSON.parse(data)
    $host = config['host']
    $port = config['port']
    $addr = config['addr']
  rescue
    puts "Couldn't read config/config.json file properly. Exiting"
    exit! 1
  end
end


#
# HANDLE ARGV

if ARGV[0] == "server"
  puts "Starting in background..."
  pid = fork do
    run()
  end

  Process.detach(pid)
else
  puts "Staying in foreground..."
  run()
end

