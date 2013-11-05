
file = File.expand_path(__FILE__)
dir = File.dirname(file)

def rqrq_rqenv_add_path_if_needed(path)
 if not $LOAD_PATH.include?(path)
   $LOAD_PATH.unshift path
 end
end

rqrq_rqenv_add_path_if_needed(File.expand_path("#{dir}/gems/json_pure-1.8.1/lib"))
rqrq_rqenv_add_path_if_needed(File.expand_path("#{dir}/gems/rack-1.5.2/lib"))
rqrq_rqenv_add_path_if_needed(File.expand_path("#{dir}/gems/tilt-1.4.1/lib"))
rqrq_rqenv_add_path_if_needed(File.expand_path("#{dir}/gems/rack-protection-1.5.1/lib"))
rqrq_rqenv_add_path_if_needed(File.expand_path("#{dir}/gems/sinatra-1.4.4/lib"))
