
# Setup ENV
Dir.glob(File.join("code", "vendor", "gems", "*", "lib")).each do |lib|
  $LOAD_PATH.unshift(File.expand_path(lib))
end

require 'rubygems'
gem_paths = [File.expand_path(File.join("code", "vendor", "gems")),  Gem.default_dir]
Gem.clear_paths
Gem.send :set_paths, gem_paths.join(":")

p ARGV.inspect

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
p args 


require 'code/queueclient'

# Which queue am I bound to?
# TODO: later 

# Create a message
#   - dest queue
#   - relay_ok = default yes
#   - src id
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
  mesg = {   'dest' => args['dest'],
              'src' => args['src'],
           'param1' => args['params1'],
           'param2' => args['params2'],
           'param3' => args['params3'],
           'param4' => args['params4'],
  }
  result = qc.create_message(mesg)
  p "Message: #{result} inserted into queue: #{q_name}"

end

if ARGV[0] == 'prepmesg'
end

if ARGV[0] == 'attach'
end

if ARGV[0] == 'commit'
end

