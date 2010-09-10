desc  'Set up a default configuration, launch RQ, run the RQ test script'
task  :test_rq do

  # Top level directories that we need
  dirs = ["config", "queue.noindex"]
  # Queue directories
  queuedirs = ["cleaner", "relay", "webhook"]
  # Queue subdirs
  queuedircontents = ["done", "err", "pause", "prep", "que", "relayed", "run"]
  
  # Default config files we will need
  configfiles = { "rqconfig" => %q({"env":"test","port":"5000","host":"localhost","addr":"0.0.0.0"}),
    "cleanerconfig" => %q({"ordering":"ordered","script":".\/code\/cleaner_script.rb","name":"cleaner","fsync":"no-fsync","oper_status":"UP","admin_status":"UP","num_workers":"1"}),
    "relayconfig" => %q({"name":"relay","script":".\/code\/relay_script.rb","ordering":"ordered","fsync":"no-fsync","oper_status":"UP","admin_status":"UP","num_workers":"1"}),
    "webhookconfig" => %q({"ordering":"ordered","script":".\/code\/webhook_script.rb","name":"webhook","fsync":"no-fsync","oper_status":"UP","admin_status":"UP","num_workers":"1"}) }
  
  # Create the top level dirs
  dirs.each do |dirname|
    Dir.mkdir( dirname )
  end
  
  # .noindex is a Mac thing to keep MacOS from indexing all the files in this directory
  system("ln -s queue.noindex queue")
  
  # Write the main RQ config file
  File.open( "config/config.json", 'w' ) { |f| f.write(configfiles['rqconfig']) }
  
  # Create queue directory structures and configs
  queuedirs.each do |dirname|
    Dir.mkdir( "queue.noindex/#{dirname}" )
    File.open( "queue.noindex/#{dirname}/config.json", 'w' ) { |f| f.write(configfiles["#{dirname}config"]) }
    queuedircontents.each do |contentdir|
      Dir.mkdir( "queue.noindex/#{dirname}/#{contentdir}" )
    end
  end
  
  def run_command(command)
    puts "Trying to run #{command}..."
    system(command)
    if $? != 0
      abort("#{command} did not run successfully!")
    end
  end

  # Try to start RQ and run the test script
  run_command("bin/queuemgr_ctl start")
  run_command("bin/web_server.sh")
  run_command("bin/check_rq -p 5000")

end
