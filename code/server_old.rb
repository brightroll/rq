
Dir.glob(File.join("code", "vendor", "gems", "*", "lib")).each do |lib|
  $LOAD_PATH.unshift(File.expand_path(lib))
end

require 'rubygems'
gem_paths = [File.expand_path(File.join("code", "vendor", "gems")),  Gem.default_dir]
Gem.clear_paths
Gem.send :set_paths, gem_paths.join(":")

require 'sinatra'
require 'erb'

require 'code/install'

builder = Rack::Builder.new do

disable :run
#get '/' do
#  if not File.exists?('config')
#    redirect('install')
#  else
#    erb :index
#  end
#end

  map "/install" do
    run RQ::Install
  end

end



