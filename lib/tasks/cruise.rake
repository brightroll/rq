desc  "Build using Cruise Control and increment version" 
task  :cruise => [:increment_ver, :update_version, :tag]
