
desc  'Increment the version.rb file with a new version number'
task  :increment_ver do
    version_file = "version.rb"
    mydate = Time.now.strftime("%Y%m%d")
    buffer = []
    file = File.open(version_file, 'r') 
    begin
      while ( line  = file.readline )
        if line =~ /VERSION_NUMBER = \"(\d{8})\.(\d+)\"/
          if $1 == mydate
            buffer.push( sprintf "VERSION_NUMBER = \"%d.%d\"\n" %[$1, $2.succ] )
          else
            buffer.push( sprintf "VERSION_NUMBER = \"%d.%d\"\n" %[mydate, 1] )
          end
        else
          buffer.push(line)
        end
      end
    rescue
      file.close
    end
    myfile = File.open(version_file, 'w+') 
      buffer.each do |bline|
      myfile.puts(bline)
      end
    myfile.close

end

desc  'Check the updated version number back into git'
task  :update_version do
  #need to git push the new version number back to the repo 
  sh %{ git commit version.rb -m "increment VERSION_NUMBER" && git push }
end
