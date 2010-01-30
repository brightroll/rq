$:.unshift(File.join(File.dirname(__FILE__), ".."))

require 'gems/environment'
require 'rubygems'

## Setup ENV
#Dir.glob(File.join("code", "vendor", "gems", "*", "lib")).each do |lib|
#  $LOAD_PATH.unshift(File.expand_path(lib))
#end
#
#gem_paths = [File.expand_path(File.join("code", "vendor", "gems")),  Gem.default_dir]
#Gem.clear_paths
#Gem.send :set_paths, gem_paths.join(":")

#p ARGV.inspect

def process_args(arg_list)
  input = { }

  input[:cmd]  = arg_list.shift
  input[:xtra] = []

  # TODO: do this in a functional manner to cleanse 
  i = 0
  while i < arg_list.length
    if arg_list[i].index('--')
      # Ok, we have a param

      # ... does it have an '='
      if arg_list[i].index('=')
        parts = arg_list[i].split('=', 2)
        input[parts[0][2..-1]] = parts[1]
        i += 1
        next
      elsif (i+1 < arg_list.length) && (arg_list[i+1].index('--') == nil)
        input[arg_list[i][2..-1]] = arg_list[i+1]
        i += 2
        next
      end

      input[arg_list[i][2..-1]] = true
      i += 1
    else
      input[:xtra] << arg_list[i]
      i += 1
    end
  end

  input
end

args = process_args(ARGV)
#p args 


require 'code/queueclient'

def check_attachment(msg)
  # simple early check, ok, now check for pathname
  return [false, "No such file #{msg['pathname']} to attach to message"] unless File.exists?(msg['pathname'])
  return [false, "Attachment currently cannot be a directory #{msg['pathname']}"] if File.directory?(msg['pathname'])
  return [false, "Attachment currently cannot be read: #{msg['pathname']}"] unless File.readable?(msg['pathname'])
  return [false, "Attachment currently not of supported type: #{msg['pathname']}"] unless File.file?(msg['pathname'])
  return [true, '']
end


# Which queue am I bound to?
# TODO: later 

# Create a message
#   - 'dest' queue
#   - 'src' id
#   - relay_ok = default yes
#   - param[1234]
if args[:cmd] == 'sendmesg'
  q_name = args['dest']

  if (q_name.index('http:') == 0) && args.has_key?('relay-ok')
    q_name = 'relay'
  else
    throw :halt, [404, 'Sorry - cannot relay message']
  end

  qc = RQ::QueueClient.new(q_name)

  if not qc.exists?
    throw :halt, [404, "404 - Queue not found"]
  end

  # Construct message
  mesg = {}
  keys = %w(dest src param1 param2 param3 param3)
  keys.each do
    |key|
    next unless args.has_key?(key)
    mesg[key] = args[key]
  end
  result = qc.create_message(mesg)
  p "Message: #{result.inspect} inserted into queue: #{q_name}"

end

if args[:cmd] == 'prepmesg'
  q_name = args['dest']

  if (q_name.index('http:') == 0)
    if args.has_key?('relay-ok')
      q_name = 'relay'
    else
      throw :halt, [404, 'Sorry - cannot relay message']
    end
  end

  qc = RQ::QueueClient.new(q_name)

  if not qc.exists?
    throw :halt, [404, "404 - Queue not found"]
  end

  # Construct message
  mesg = {}
  keys = %w(dest src param1 param2 param3 param3)
  keys.each do
    |key|
    next unless args.has_key?(key)
    mesg[key] = args[key]
  end
  result = qc.prep_message(mesg)
  print "#{result[0]} #{result[1]}\n"
  #p "Message: #{result} inserted into queue: #{q_name}"
end

if args[:cmd] == 'attachmesg'
  full_mesg_id = args['msg_id']

  q_name = full_mesg_id[/\/q\/([^\/]+)/, 1]
  msg_id = full_mesg_id[/\/q\/[^\/]+\/([^\/]+)/, 1]

  qc = RQ::QueueClient.new(q_name)

  if not qc.exists?
    throw :halt, [404, "404 - Queue not found"]
  end

  # Construct message for queue mgr
  msg = {'msg_id' => msg_id}
  keys = %w(pathname name local_fs_only)
  keys.each do
    |key|
    next unless args.has_key?(key)
    msg[key] = args[key]
  end

  msg['pathname'] = File.expand_path(msg['pathname'])
  results = check_attachment(msg)
  if not results[0]
    p results[1]
    throw :halt, [404, "404 - #{results[0]}"]
  end
  result = qc.attach_message(msg)
  print "#{result[0]} #{result[1]} for Message: #{full_mesg_id} attachment\n"
end

if args[:cmd] == 'commitmesg'
  full_mesg_id = args['msg_id']

  q_name = full_mesg_id[/\/q\/([^\/]+)/, 1]
  msg_id = full_mesg_id[/\/q\/[^\/]+\/([^\/]+)/, 1]

  qc = RQ::QueueClient.new(q_name)

  if not qc.exists?
    throw :halt, [404, "404 - Queue not found"]
  end

  # Construct message for queue mgr
  mesg = {'msg_id' => msg_id }
  result = qc.commit_message(mesg)
  print "#{result[0]} #{result[1]}\n"
  #p "#{result} for Message: #{mesg['msg-id']} committed"
end

if args[:cmd] == 'statusmesg'
  full_mesg_id = args['msg_id']

  q_name = full_mesg_id[/\/q\/([^\/]+)/, 1]
  msg_id = full_mesg_id[/\/q\/[^\/]+\/([^\/]+)/, 1]

  qc = RQ::QueueClient.new(q_name)

  if not qc.exists?
    throw :halt, [404, "404 - Queue not found"]
  end

  # Construct message for queue mgr
  mesg = {'msg_id' => msg_id }
  result = qc.get_message(mesg)
  if result[0] == 'ok'
    print "#{result[0]} #{result[1]['status']}\n"
  else
    print "#{result[0]} #{result[1]}\n"
  end
end

if args[:cmd] == 'statuscountmesg'
  full_mesg_id = args['msg_id']

  q_name = full_mesg_id[/\/q\/([^\/]+)/, 1]
  msg_id = full_mesg_id[/\/q\/[^\/]+\/([^\/]+)/, 1]

  qc = RQ::QueueClient.new(q_name)

  if not qc.exists?
    throw :halt, [404, "404 - Queue not found"]
  end

  # Construct message for queue mgr
  mesg = {'msg_id' => msg_id }
  result = qc.get_message(mesg)
  if result[0] == 'ok'
    print "#{result[0]} #{result[1].fetch('count', '0')}\n"
  else
    print "#{result[0]} #{result[1]}\n"
  end
end

if args[:cmd] == 'attachstatusmesg'
  full_mesg_id = args['msg_id']

  q_name = full_mesg_id[/\/q\/([^\/]+)/, 1]
  msg_id = full_mesg_id[/\/q\/[^\/]+\/([^\/]+)/, 1]

  qc = RQ::QueueClient.new(q_name)

  if not qc.exists?
    throw :halt, [404, "404 - Queue not found"]
  end

  # Construct message for queue mgr
  mesg = {'msg_id' => msg_id }
  result = qc.get_message(mesg)
  if result[0] == 'ok'
    ents = []
    if result[1].has_key?('_attachments')
      result[1]['_attachments'].each do
        |k,v|
        ents << [k, v['md5']]
      end
    end
    print "#{result[0]} #{ents.length}\n"
    ents.each do
      |ent|
      print "#{ent[0]} #{ent[1]}\n"
    end
  else
    print "#{result[0]} #{result[1]}\n"
  end
end
