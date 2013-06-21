#!/usr/bin/env ruby

def log(mesg)
  File.open('relay.log', "a") do |f|
    f.write("#{Process.pid} - #{Time.now} - #{mesg}\n")
  end
end

# Had to use \n
# I tried to use \000 but bash barfed on me
def write_status(state, mesg = '')
  io = IO.for_fd(ENV['RQ_PIPE'].to_i)
  msg = "#{state} #{mesg}\n"
  io.syswrite(msg)
end

write_status('run', "just started")
sleep 2.0
p "TESTTESTTEST"
write_status('run', "a little after just started")
sleep 2.0

cwd = Dir.pwd

log(cwd)

log(ENV.inspect)

log(`lsof -p $$`)
write_status('run', "post lsof")

5.times do
  |count|
  log("sleeping")
  write_status('run', "#{count} done - #{5 - count} to go")
  sleep 1.0
end
log("done sleeping")


log("done")
write_status('done')
exit(0)
