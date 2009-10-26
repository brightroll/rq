#!/usr/bin/env ruby


# 
def log(mesg)
  File.open('relay.log', "a") do
    |f|
    f.write("#{Process.pid} - #{Time.now} - #{mesg}\n")
  end
end

p "TESTTESTTEST"

cwd = Dir.pwd

log(cwd)

log(ENV.inspect)

log(`lsof -p $$`)

log("sleeping")
sleep 5.0
log("done sleeping")


log("done")
exit(0)
