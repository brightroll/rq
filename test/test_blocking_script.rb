#!/usr/bin/env ruby

def write_status(state, mesg = '')
  io = IO.for_fd(ENV['RQ_WRITE'].to_i)
  msg = "#{state} #{mesg}\n"
  io.syswrite(msg)
end

write_status('run', "just started")

unlock_file = "#{ENV['PWD']}/test/tmp/#{ENV['RQ_PARAM2']}"

puts unlock_file

until File.file?(unlock_file)
  puts "File not found, going to sleep and try again....\n"
  sleep(0.25)
end

puts "done"
write_status('done')
exit(0)
