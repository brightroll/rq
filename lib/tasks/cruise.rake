desc  "Build using Cruise Control and increment version" 
task  :cruise => [:test_rq, :increment_ver, :update_version]
