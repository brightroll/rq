dir = File.dirname(__FILE__)

def rqrq_rqenv_add_path_if_needed(path)
 if not $LOAD_PATH.include?(path)
   $LOAD_PATH.unshift path
 end
end

rqrq_rqenv_add_path_if_needed(File.expand_path("#{dir}/gems/json_pure-1.1.6/lib"))
rqrq_rqenv_add_path_if_needed(File.expand_path("#{dir}/gems/rack-1.0.0/lib"))
rqrq_rqenv_add_path_if_needed(File.expand_path("#{dir}/gems/sinatra-0.9.4/lib"))
