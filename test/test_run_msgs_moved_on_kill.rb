#!/usr/bin/env ruby
$: << File.expand_path('..', File.dirname(__FILE__))

require 'vendor/environment'
require 'net/http'
require 'uri'
require 'fileutils'
require 'fcntl'
require 'json'

#+ Use a new queue test_run_states with num_workers 3
#+ Inject two slow running messages into the queue
#- Set que admin pause
#- Stop the queue
#- Kill the workers
##- Verify processes in run killed
#- Restart the queue administratively pause
#- Verify nothing in run dirs
#- Verify nothing in run state


## TEST SECTION

$rq_port = (ENV['RQ_PORT'] || 3333).to_i

def is_pid_alive?(pid)
  begin
    Process.kill(0, pid)
  rescue
    return false
  end

  return true
end

def send_mesg(mesg)
  form = { :mesg => mesg.to_json }

  # send the message
  remote_q_uri = "http://127.0.0.1:#{$rq_port}/q/test_run"
  res = Net::HTTP.post_form(URI.parse(remote_q_uri + "/new_message"), form)

  if res.code != '200'
    print "FAILED system didn't create test message properly\n"
    print "#{res.inspect}\n"
    exit 1
  end

  result = JSON.parse(res.body)

  if result[0] != 'ok'
    print "FAILED system didn't create test message properly : #{res.body}\n"
    exit 1
  end

  print "Committed message: #{result[1]}\n"

  msg_id = result[1][/\/q\/[^\/]+\/([^\/]+)/, 1]

  print "Msg ID: #{msg_id}\n"

  msg_id
end

def get_queue_status()
  uri_str = "http://127.0.0.1:#{$rq_port}/q/test_run.json"
  res = Net::HTTP.get_response(URI.parse(uri_str))

  if res.code != '200'
    print "FAILED system didn't get status of test_run que properly\n"
    print "#{res.inspect}\n"
    exit 1
  end

  result = JSON.parse(res.body)
end

# no relay_ok, this should go direct to the queue
mesg = {   'dest' => "http://127.0.0.1:#{$rq_port}/q/test_run",
            'src' => 'test',
         'param1' => 'slow3',
       }

# Use a new queue test_run_states with num_workers 3

# Inject two slow running messages into the queue
msg1 = send_mesg(mesg)
msg2 = send_mesg(mesg)

proper = false
4.times do
  result = get_queue_status()
  if result['run_size'] == 2
    proper = true
    break 
  end
  sleep(0.10)
end

if not proper
  print "FAILED both messages are not in proper run state\n"
  exit 1
end

# Set que admin pause
File.open('config/test_run.pause', 'w') { |f| f.write(' ') }
at_exit { File.unlink('config/test_run.pause') }

# Stop the queue
`./bin/rq-mgr stop`

# Kill the workers
begin
  pid1 = File.read("queue/test_run/run/#{msg1}/pid").to_i
  Process.kill("TERM", pid1)
  pid2 = File.read("queue/test_run/run/#{msg2}/pid").to_i
  Process.kill("TERM", pid2)
rescue Exception => e
  puts "Error killing pid1 (#{pid1}) or pid2 (#{pid2}): #{e.message}"
end

pid1_dead = false
pid2_dead = false

4.times do
  if is_pid_alive?(pid1)
    sleep(0.25)
  else
    pid1_dead = true
    break
  end
end

4.times do
  if is_pid_alive?(pid2)
    sleep(0.25)
  else
    pid2_dead = true
    break
  end
end

# Verify processes in run killed
if !pid1_dead
  print "FAILED #{msg1} is still alive after shutdown\n"
  exit 1
end
if !pid2_dead
  print "FAILED #{msg2} is still alive after shutdown\n"
  exit 1
end

# Restart the queue administratively pause
`./bin/rq-mgr start`

# TODO: properly check for proper start

#sleep(1)
started = false
5.times do
  # Verify nothing in run dirs
  if not Dir.glob('queue/test_run/run/*').empty?
    sleep(1)
  else
    started = true
    break
  end
end

if !started
    print "FAILED - run dir is not empty after restart\n"
    exit 1
end

# Verify nothing in run state
result = get_queue_status()
if result['run_size'] != 0
  print "FAIL - queue has non 0 run que value: '#{result['run_size']}'\n"
  exit 1
end
if result['que_size'] != 2
  print "FAIL - queue has non 2 que value: '#{result['que_size']}'\n"
  exit 1
end

puts "ALL DONE SUCCESSFULLY"

