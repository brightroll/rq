include FileUtils

# Load any app level custom rakefile extensions from lib/tasks
tasks_path = File.join(File.dirname(__FILE__), "lib", "tasks")
rake_files = Dir["#{tasks_path}/*.rake"]
rake_files.each{|rake_file| load rake_file }

##############################################################################
#  ADD YOUR CUSTOM TASKS IN /lib/tasks
#  NAME YOUR RAKE FILES file_name.rake
##############################################################################
