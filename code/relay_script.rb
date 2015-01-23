#!/usr/bin/env ruby
$:.unshift(File.join(File.dirname(__FILE__), ".."))

require 'vendor/environment'
require 'json'
require 'net/http'
require 'uri'
require 'fileutils'
require 'digest'
require 'resolv-replace'
require 'code/queueclient'

def log(mesg)
  puts "\033[0;36m#{$$} - #{Time.now}\033[0m - #{mesg}"
  $stdout.flush
end

log(Dir.pwd.inspect)

# Setup a global binding so the GC doesn't close the file
$RQ_IO = IO.for_fd(ENV['RQ_WRITE'].to_i)

# Had to use \n
# I tried to use \000 but bash barfed on me
def write_status(state, mesg = '')
  msg = "#{state} #{mesg}\n"
  $RQ_IO.syswrite(msg)
  log("#{state} #{mesg}")
end

def soft_fail(mesg = 'soft fail')
  count = ENV['RQ_COUNT'].to_i
  wait_seconds = count * count * 10
  write_status('resend', "#{wait_seconds}-#{mesg}")
  log("RESEND - #{wait_seconds} - #{count} - #{mesg}")
  exit(0)
end

def get_id()
  return nil unless File.exist?('relay_id')
  File.open('relay_id', "r") do
    |f|
    x = f.read
    log("Using prior relay_id: #{x}")
    return x
  end

  return nil
end

def set_id(msg_id)
  File.open('relay_id.tmp', "w") do
    |f|
    f.write(msg_id)
  end
  File.rename('relay_id.tmp', 'relay_id')

  log("Now using relay_id: #{msg_id}")

  return true
end

def erase_id()
  File.unlink('relay_id') rescue nil
end

def file_md5(path)
  hasher = Digest::MD5.new

  File.open(path, 'r') do |file|
    hasher.update(file.read(32768)) until file.eof
  end

  result = hasher.hexdigest
end

# Get count, if too high, big fail
count = ENV['RQ_COUNT'].to_i
if count > 15
  write_status('run', "RQ_COUNT > 15 - failing")
  write_status('fail', "RQ_COUNT > 15 FAIL")
end

# Get destination queue
dest = ENV['RQ_DEST']
log("dest - #{dest}")

force = false
fake_fail = false
remote_delivery = true

if (ENV['RQ_DEST'] == 'http://127.0.0.1:3333/q/test') &&
  (ENV['RQ_PARAM2'] == 'the_mighty_rq_force')
  force = true
  log("TEST MODE force = true")

  if ENV['RQ_PARAM3'] == 'fail' && ENV['RQ_COUNT'] == '0'
    fake_fail = true
    log("TEST MODE fake_fail = true")
  end
end

# If this was a force_remote
if ENV['RQ_FORCE_REMOTE'] == '1'
  log("FORCE REMOTE")
  remote_delivery = true
end

if remote_delivery
  # Get the URL
  remote_q_uri = dest[/(.*?\/q\/[^\/]+)/, 1]

  #write_status('err', "Cannot do remote queue relay yet.")
  #exit(0)

  ##
  ## REMOTE QUEUE DELIVERY
  ##

  ## Check if destq is relay, which is invalid
  #destq = ENV['RQ_DEST_QUEUE']
  #if destq == 'relay'
  #  write_status('err', "Message dest queue is relay. Cannot have that.")
  #  exit(0)
  #end

  ## If valid queue, attempt to relay message
  #require 'code/queueclient'
  #qc = RQ::QueueClient.new(destq, "../../../../..")

  #log("Attempting connect with #{destq}")

  #if not qc.exists?
  #  soft_fail("#{destq} does not exist")
  #end

  # 2 phase commit section

  new_msg_id = get_id()         # Do we have an ID already

                                # Yes, skip prep...
  if nil == new_msg_id          # No, do prep, and store id

    # COPIED FROM queue.rb/get_message
    # Get data about message
    curr_msg = nil
    begin
      data = File.read("../msg")  # TODO: eliminate this cheat
      curr_msg = JSON.parse(data)
    rescue
      # TODO: Log to private log here
      soft_fail("Couldn't read message data from file")
    end

    # Increment count
    curr_msg['count'] = curr_msg.fetch('count', 0) + 1

    # Construct message
    mesg = {}
    keys = %w(dest src count max_count param1 param2 param3 param4 post_run_webhook orig_msg_id)
    keys.each do
      |key|
      next unless curr_msg.has_key?(key)
      mesg[key] = curr_msg[key]
    end

    mesg['_method'] = 'prep'

    log("attempting remote #{remote_q_uri}")
    # Connect to that site for that queue and submit the message
    uri = remote_q_uri + "/new_message"
    begin
      res = Net::HTTP.post_form(URI.parse(uri), {:x_format => 'json', :mesg => mesg.to_json })
    rescue Exception
      log("Net::HTTP exception: " + $!.to_s)
      # THIS IS SO BAD, BUT HEY SUCH IS LIFE UNTIL 1.9
      # WHY?
      # BEST DESCRIPTION IS HERE http://jerith.livejournal.com/40063.html
      soft_fail("Could not connect to or parse URL: #{uri}")
    end

    if res.code == '200'
      json_result = JSON.parse(res.body)
      if json_result[0] == 'ok'
        new_msg_id = json_result[1]
        set_id(new_msg_id)
      else
        soft_fail("Couldn't queue message: #{json_result.inspect}")
      end
      if fake_fail # We are exiting anyways
        set_id(new_msg_id + "00110011")
        soft_fail("FAKE FAIL - Couldn't queue message: #{json_result.inspect}")
      end
    else
      puts res.body
      soft_fail("Couldn't queue message: #{res.inspect}")
    end
  end

  # Pull the Short MSG ID out of the Full Msg Id
  #q_name = full_mesg_id[/\/q\/([^\/]+)/, 1]
  new_short_msg_id = new_msg_id[/\/q\/[^\/]+\/([^\/]+)/, 1]

  # Idempotently attach any attachments
  if File.exist?('../attach')
    log("attempting sending attach")
    entries = Dir.entries('../attach').reject { |e| e.start_with?('.') }

    fnames =  entries.select { |e| File.file?("../attach/#{e}") }
    fnames.each do
      |fname|

      log("attempting sending attach #{fname}")

      md5 = file_md5("../attach/#{fname}")

      pipe_res = `curl -0 -s -F x_format=json -F filedata=@../attach/#{fname} -F pathname=#{fname} -F msg_id=#{new_short_msg_id} #{new_msg_id}/attach/new`
      #p $?
      #p pipe_res
      # Get the URL
      #res = Net::HTTP.post_form(URI.parse(remote_q_uri + "/#{msg_id}/attach/new"), form)

      if $?.exitstatus != 0
        soft_fail("Couldn't run curl to attach to message: #{$?.exitstatus.inspect}")
      end

      begin
        result = JSON.parse(pipe_res)
      rescue Exception
        log("Could not parse JSON")
        log(pipe_res)
        write_status('err', "BAD JSON")
        exit(1)
      end

      if result[0] != 'ok'
        if result[0] == 'fail' and result[1] == 'cannot find message'
          erase_id()
          soft_fail("Remote message [#{new_msg_id}] disappeared: #{pipe_res}. Getting new id.")
        end
        soft_fail("Couldn't attach to test message properly : #{pipe_res}")
      end

      if result[1] != "#{md5}-Attached successfully"
        log("Sorry, system couldn't attach to test message properly : #{pipe_res}\n")
        log("Was expecting: #{md5}-Attached successfully\n")
        soft_fail("Couldn't attach to test message properly - md5 mismatch : #{pipe_res}")
      end

    end
  end

  # Commit ID
  form = { :x_format => 'json', '_method' => 'commit', :msg_id => new_short_msg_id }

  # Get the URL
  uri = new_msg_id
  begin
    res = Net::HTTP.post_form(URI.parse(uri), form)
  rescue Exception
    log("Net::HTTP exception: " + $!.to_s)
    # THIS IS SO BAD, BUT HEY SUCH IS LIFE UNTIL 1.9
    # WHY?
    # BEST DESCRIPTION IS HERE http://jerith.livejournal.com/40063.html
    soft_fail("Could not connect to or parse URL: #{uri}")
  end

  if res.code != '200'
    soft_fail("Couldn't commit message: #{res.inspect}")
  end

  json_result = JSON.parse(res.body)

  if json_result[0] != 'ok'
    if json_result[0] == 'fail' and json_result[1] == 'cannot find message'
      erase_id()
      soft_fail("Remote message [#{new_msg_id}] disappeared: #{json_result.inspect}. Getting new id.")
    end
    soft_fail("Couldn't commit message: #{json_result.inspect}")
  else
    erase_id()
    write_status('relayed', new_msg_id)
  end

  exit(0)
end

##
## LOCAL QUEUE INJECTION (A LOT LIKE REMOTE)
##

# Check if destq is relay, which is invalid
destq = ENV['RQ_DEST_QUEUE']
if destq == 'relay'
  write_status('err', "Message dest queue is relay. Cannot have that.")
  exit(0)
end

# If valid queue, attempt to relay message
log("Attempting connect with local queue #{destq}")

qc = RQ::QueueClient.new(destq, "../../../../..") rescue soft_fail("#{destq} does not exist")

# 2 phase commit section

new_msg_id = get_id()         # Do we have an ID already

                              # Yes, skip prep...
if nil == new_msg_id          # No, do prep, and store id

  # COPIED FROM queue.rb/get_message
  # Get data about message
  curr_msg = nil
  begin
    data = File.read("../msg")  # TODO: eliminate this cheat
    curr_msg = JSON.parse(data)
  rescue
    # TODO: Log to private log here
    soft_fail("Couldn't read message data from file")
  end


  # Increment count
  curr_msg['count'] = curr_msg.fetch('count', 0) + 1

  # Construct message
  mesg = {}
  keys = %w(dest src count max_count param1 param2 param3 param4 post_run_webhook orig_msg_id)
  keys.each do
    |key|
    next unless curr_msg.has_key?(key)
    mesg[key] = curr_msg[key]
  end

  result = qc.prep_message(mesg)

  if result && (result[0] == "ok")
    new_msg_id = result[1]
    set_id(new_msg_id)
  else
    soft_fail("Couldn't queue message: #{result[0]} - #{result[1]}")
  end
end

# Pull the Short MSG ID out of the Full Msg Id
#q_name = full_mesg_id[/\/q\/([^\/]+)/, 1]
new_short_msg_id = new_msg_id[/\/q\/[^\/]+\/([^\/]+)/, 1]

log("attempting local send attach")

# Idempotently attach any attachments
if File.exist?('../attach')
  entries = Dir.entries('../attach').reject { |e| e.start_with?('.') }

  fnames =  entries.select { |e| File.file?("../attach/#{e}") }
  fnames.each do
    |fname|

    log("attempting local send attach #{fname}")
    mesg = {'msg_id' => new_short_msg_id,
      'pathname' => File.expand_path("../attach/#{fname}")
    }
    result = qc.attach_message(mesg)

    if result == nil
      soft_fail("Couldn't attach file: #{mesg}")
    end
    if result && (result[0] == false)
      soft_fail("Couldn't attach message: #{result[0]} - #{result[1]}")
    end
  end

end

# Commit ID
mesg = {'msg_id' => new_short_msg_id, }
result = qc.commit_message(mesg)

if result && (result[0] == "ok")
  erase_id()
  write_status('relayed', new_msg_id)
else
  soft_fail("Couldn't commit message: #{result[0]} - #{result[1]}")
end


