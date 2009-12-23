#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'fileutils'
require 'fcntl'
require 'digest'

# 
def log(mesg)
  File.open('relay.log', "a") do
    |f|
    f.write("#{Process.pid} - #{Time.now} - #{mesg}\n")
  end
end


Dir.glob(File.join("..", "..", "..", "..", "..", "code", "vendor", "gems", "*", "lib")).each do |lib|
  $LOAD_PATH.unshift(File.expand_path(lib))
end
Dir.glob(File.join("..", "..", "..", "..", "..")).each do |lib|
  $LOAD_PATH.unshift(File.expand_path(lib))
end


require 'rubygems'
gem_paths = [File.expand_path(File.join("..", "..", "..", "..", "..", "code", "vendor", "gems")),  Gem.default_dir]
Gem.clear_paths
Gem.send :set_paths, gem_paths.join(":")

#log($LOAD_PATH.inspect)
log(Dir.pwd.inspect)
#log(gem_paths.inspect)

require 'json'

# Had to use \n
# I tried to use \000 but bash barfed on me
def write_status(state, mesg = '')
  io = IO.for_fd(ENV['RQ_PIPE'].to_i)
  msg = "#{state} #{mesg}\n"
  log("#{state} #{mesg}")
  io.syswrite(msg)
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

  return true
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
  write_status('fail', "#{wait_seconds}-#{mesg}")
end

# Get destination queue

this_system = ENV['RQ_HOST']
dest = ENV['RQ_DEST']

log("dest - #{dest}")
# If host different, stick in err for now
if dest.index(this_system) != 0

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
    keys = %w(dest src count param1 param2 param3 param3)
    keys.each do
      |key|
      next unless curr_msg.has_key?(key)
      mesg[key] = curr_msg[key]
    end

    mesg['_method'] = 'prep'

    # Connect to that site for that queue and submit the message
    # Net::HTTP.get_response(URI.parse(remote_q_uri))
    res = Net::HTTP.post_form(URI.parse(remote_q_uri + "/new_message"),
                              {:x_format => 'json', :mesg => mesg.to_json })


    if res.code == '200'
      json_result = JSON.parse(res.body)
      if json_result[0] == 'ok'
        new_msg_id = json_result[1]
        set_id(new_msg_id)
      else
        soft_fail("Couldn't queue message: #{json_result.inspect}")
      end
    else
      soft_fail("Couldn't queue message: #{res.inspect}")
    end
  end

  # Pull the Short MSG ID out of the Full Msg Id
  #q_name = full_mesg_id[/\/q\/([^\/]+)/, 1]
  new_short_msg_id = new_msg_id[/\/q\/[^\/]+\/([^\/]+)/, 1]

  # Idempotently attach any attachments
  if File.exists?('../attach')
    entries = Dir.entries('../attach').reject { |e| e.index('.') == 0 }

    fnames =  entries.select { |e| File.file?("../attach/#{e}") }
    fnames.each do
      |fname|

      md5 = file_md5("../attach/#{fname}")

      pipe_res = `curl -s -F filedata=@../attach/#{fname} -F pathname=#{fname} -F msg_id=#{new_short_msg_id} -F x_format=json #{remote_q_uri}/#{new_short_msg_id}/attach/new`
      #p $?
      #p pipe_res
      # Get the URL
      #res = Net::HTTP.post_form(URI.parse(remote_q_uri + "/#{msg_id}/attach/new"), form)

      if $?.exitstatus != 0
        soft_fail("Couldn't run curl to attach to message: #{$?.exitstatus.inspect}")
      end

      result = JSON.parse(pipe_res)

      if result[0] != 'ok'
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
  res = Net::HTTP.post_form(URI.parse(remote_q_uri + "/#{new_short_msg_id}"), form)

  if res.code != '200'
    soft_fail("Couldn't commit message: #{res.inspect}")
  end

  json_result = JSON.parse(res.body)

  if json_result[0] != 'ok'
    soft_fail("Couldn't commit message: #{json_result.inspect}")
  else
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
require 'code/queueclient'
qc = RQ::QueueClient.new(destq, "../../../../..")

log("Attempting connect with #{destq}")

if not qc.exists?
  soft_fail("#{destq} does not exist")
end

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
  keys = %w(dest src count param1 param2 param3 param3)
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

# Idempotently attach any attachments
if File.exists?('attach')
  entries = Dir.entries('attach').reject { |e| e.index('.') == 0 }

  fnames =  entries.select { |e| File.file?("attach/#{e}") }
  fnames.each do
    |fname|

    mesg = {'msg_id' => new_short_msg_id,
      'pathname' => File.expand_path(fname)
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
  write_status('relayed', new_msg_id)
else
  soft_fail("Couldn't commit message: #{result[0]} - #{result[1]}")
end


