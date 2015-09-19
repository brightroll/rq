#!/usr/bin/env ruby
$:.unshift(File.join(File.dirname(__FILE__), ".."))

require 'vendor/environment'
require 'json'
require 'net/http'
require 'net/http/post/multipart'
require 'uri'
require 'fileutils'
require 'digest'
require 'resolv-replace'

def log(mesg)
  puts "\033[0;36m#{$$} - #{Time.now}\033[0m - #{mesg}"
  $stdout.flush
end

log(Dir.pwd.inspect)

# Setup a global binding so the GC doesn't close the file
$RQ_IO = IO.for_fd(ENV['RQ_WRITE'].to_i)

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
  exit
end

def set_id(msg_id)
  File.open('relay_id.tmp', 'w') do |f|
    f.write(msg_id)
  end
  File.rename('relay_id.tmp', 'relay_id')
  log("Now using relay_id: #{msg_id}")
end

def erase_id
  File.unlink('relay_id') rescue nil
end

def file_md5(path)
  hasher = Digest::MD5.new

  File.open(path, 'r') do |file|
    hasher.update(file.read(32768)) until file.eof
  end

  hasher.hexdigest
end

# Get count, if too high, big fail
count = ENV['RQ_COUNT'].to_i
if count > 15
  write_status('run', "RQ_COUNT > 15 - failing")
  write_status('fail', "RQ_COUNT > 15 FAIL")
  exit
end

# Check that we aren't in a relay loop
if ENV['RQ_ORIG_MSG_ID'].start_with?(ENV['RQ_DEST'])
  log("RQ_DEST '#{ENV['RQ_DEST']}' queue same as RQ_ORIG_MSG_ID '#{ENV['RQ_ORIG_MSG_ID']}'")
  write_status('fail', "Relay loop detected: RQ_DEST queue same as RQ_ORIG_MSG_ID")
  exit
end

# Get the URL
log("dest - #{ENV['RQ_DEST']}")

# There is a unit test for this, probably useless now
log('FORCE REMOTE') if ENV['RQ_FORCE_REMOTE']

# Fake fail is for unit testing by failure injection
fake_fail = false
if ENV['RQ_DEST'] == 'http://127.0.0.1:3333/q/test' \
   && ENV['RQ_PARAM2'] == 'the_mighty_rq_force'     \
   && ENV['RQ_PARAM3'] == 'fail'                    \
   && ENV['RQ_COUNT'] == '0'
  fake_fail = true
  log("TEST MODE fake_fail = true")
end

##
## REMOTE QUEUE DELIVERY
##

new_msg_id = File.open('relay_id', 'r').read if File.exist?('relay_id')

# If there's an existing message id, skip the prep step
# If there isn't an existing message, create one in prep state
if new_msg_id.nil?
  # Params like post_run_webhook are not passed in an ENV var,
  # cheat this by reading the message directly
  begin
    data = File.read("../msg")
    curr_msg = JSON.parse(data)
  rescue
    soft_fail("Couldn't read message data from file")
  end

  # Increment count
  curr_msg['count'] = curr_msg.fetch('count', 0) + 1

  # Construct message
  mesg = {}
  keys = %w(dest src count max_count param1 param2 param3 param4 post_run_webhook orig_msg_id)
  # mesg = Hash[zip(keys, curr_msg.values_at(*keys))]
  keys.each do |key|
    next unless curr_msg.has_key?(key)
    mesg[key] = curr_msg[key]
  end

  mesg['_method'] = 'prep'

  log("attempting remote #{ENV['RQ_DEST']}")
  # Connect to that site for that queue and submit the message
  uri = ENV['RQ_DEST'].chomp('/') + '/new_message'
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
new_short_msg_id = new_msg_id[/\/q\/[^\/]+\/([^\/]+)/, 1]

# Idempotently attach any attachments
if File.exists?('../attach')
  log("attempting sending attach")
  entries = Dir.entries('../attach').reject { |e| e.start_with?('.') }

  fnames = entries.select { |e| File.file?("../attach/#{e}") }
  fnames.each do |fname|
    log("attempting sending attach #{fname}")

    md5 = file_md5("../attach/#{fname}")

    begin
      uri = URI.parse("#{new_msg_id}/attach/new")
      req = Net::HTTP::Post::Multipart.new(uri.path,
          "filedata" => UploadIO.new("../attach/#{fname}", "application/octet-stream"),
          "pathname" => fname,
          "msg_id"   => new_short_msg_id,
          "x_format" => "json"
        )
      res = Net::HTTP.start(uri.host, uri.port) do |http|
        http.request(req)
      end
    rescue Exception
      log("Net::HTTP::Post::Multipart exception: " + $!.to_s)
      soft_fail("Could not connect to or parse URL: #{uri}")
    end

    if res.code == '200'
      result = JSON.parse(res.body)
      if result[0] != 'ok'
        if result[0] == 'fail' and result[1] == 'cannot find message'
          erase_id
          soft_fail("Remote message [#{new_msg_id}] disappeared. Getting new id.")
        end
        soft_fail("Couldn't attach to test message properly.")
      end

      if result[1] != "#{md5}-Attached successfully"
        log("Sorry, system couldn't attach to test message properly")
        log("Was expecting: #{md5}-Attached successfully")
        soft_fail("Couldn't attach to test message properly - md5 mismatch")
      end
    else
      soft_fail("Couldn't attach to test message properly - error #{res.code}")
    end
  end
end

# Commit the message
begin
  res = Net::HTTP.post_form(URI.parse(new_msg_id), {
    'msg_id'   => new_short_msg_id,
    '_method'  => 'commit',
    'x_format' => 'json',
  })
rescue Exception
  log("Net::HTTP exception: " + $!.to_s)
  # THIS IS SO BAD, BUT HEY SUCH IS LIFE UNTIL 1.9
  # WHY?
  # BEST DESCRIPTION IS HERE http://jerith.livejournal.com/40063.html
  soft_fail("Could not connect to or parse URL: #{new_msg_id}")
end

if res.code != '200'
  soft_fail("Couldn't commit message: #{res.inspect}")
end

json_result = JSON.parse(res.body)

if json_result[0] != 'ok'
  if json_result[0] == 'fail' and json_result[1] == 'cannot find message'
    erase_id
    soft_fail("Remote message [#{new_msg_id}] disappeared: #{json_result.inspect}. Getting new id.")
  end
  soft_fail("Couldn't commit message: #{json_result.inspect}")
else
  erase_id
  write_status('relayed', new_msg_id)
end

exit
