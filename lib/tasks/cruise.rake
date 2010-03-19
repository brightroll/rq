desc  "Cruise Control build and increment version" 
task  :cruise => [:increment_ver, :update_version]
