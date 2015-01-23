#!/usr/bin/env ruby

def write_status(state, mesg = '')
  io = IO.for_fd(ENV['RQ_WRITE'].to_i)
  msg = "#{state} #{mesg}\n"
  io.syswrite(msg)
end

write_status('run', 'just started')

unlock_file = File.expand_path("../tmp/#{ENV['RQ_PARAM2']}", __FILE__)

puts unlock_file

until File.file?(unlock_file)
  puts 'File not found, going to sleep and try again...'
  sleep(0.25)
end

puts 'done'
write_status('done')
exit(0)
