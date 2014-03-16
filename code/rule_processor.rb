module RQ

  class DSLArgumentError < StandardError; end
  class DSLRuleError < StandardError; end

  class Rule

    attr_accessor :data

    @@fields = [:desc, :action, :src, :dest, :route, :delay, :log, :num]

    @@rand_proc = lambda {|x| rand(x) }

    def self.rand_func=(f)
      @@rand_proc = f
    end

    def initialize()
      @data = {}
    end

    def rule(dsc)
      raise DSLArgumentError, "Wrong desc type: #{dsc.class}" unless [String, Symbol].include? dsc.class
      @data[:desc] = dsc
    end

    def action(act)
      raise DSLArgumentError.new("Action not a symbol #{act}") if act.class != Symbol
      if not [:relay, :balance, :done, :err].include? act
        raise DSLArgumentError, "Action not a valid action '#{act}'"
      end
      @data[:action] = act
    end

    def src(rgx)
      raise DSLArgumentError if rgx.class != Regexp
      @data[:src] = rgx
    end

    def dest(dst)
      raise DSLArgumentError, "Dest not a regexp"  if dst.class != Regexp
      @data[:dest] = dst
    end

    def route(*rt)
      raise DSLArgumentError, "Wrong route type: #{rt.class}" unless [String, Array].include? rt.class
      @data[:route] = rt
    end

    def log(tf)
      raise DSLArgumentError, "delay must be an boolean: #{tf}" unless (tf.class == TrueClass || tf.class == FalseClass)
      @data[:log] = tf
    end

    def delay(dly)
      raise DSLArgumentError, "delay must be an integer: #{dly}" if dly.class != Fixnum
      @data[:delay] = dly
    end

    def end_rule
      # Validate rule - raise ArgumentError if act.class != Symbol
      #$rules << self
      if [:blackhole, :err].include? @data[:action]
        @data[:log] = true
      end
      @data[:log] = @data[:log] ? true : false   # normalize to boolean

      @data[:delay] ||= 0

      if @data[:desc] != 'default'
        raise DSLRuleError, "rule must have a src or dest pattern match" unless (@data[:src] || @data[:dest])
      end

      @data[:route] ||= []

      self
    end

    def match(msg)
      return true if @desc == 'default'

      if @data[:src]
        return false unless msg['src']

        return false unless msg['src'] =~ @data[:src]
      end
      if @data[:dest]
        return false unless msg['dest']

        return false unless msg['dest'] =~ @data[:dest]
      end

      true
    end

    def inspect
      puts @data[:desc]
      fields = @@fields - [:desc, :num]
      fields.each { |k| puts "#{k.to_s} #{@data[k].to_s}" if @data[k] }
      puts
    end

    def select_hosts
      return [] if @data[:route].empty?

      rts = @data[:route]

      if @data[:action] == :relay
        # If an array of arrays, pick one from each subarray
        if rts[0].class == Array
          rts.map { |a| a[@@rand_proc.call(a.length)] }
        else
          rts
        end
      else
        # pick a random element
        [ rts[@@rand_proc.call(rts.length)] ]
      end
    end

    def process(str, num, verbose=false)
      begin
        instance_eval(str)
      rescue DSLArgumentError => ex
        if verbose
          puts "Argument error with line #{num}: [#{str.chop.to_s}]"
          puts ex.message
        end
      rescue
        if verbose
          puts "Problem with line #{num}: [#{str.chop.to_s}]"
        end
        raise
      end
    end
  end

  class RuleProcessor

    attr_accessor :rules

    def initialize(rls)
      @rules = rls
    end

    def length
      @rules.length
    end

    def first_match(o)
      @rules.find { |e| e.match(o) }
    end

    def txform_host(old, new)
      # if new has full address, we just use that
      if new.start_with?("http")
        return new
      end

      # Does new have a port
      if new !~ /:\d+/
        new += ':3333'
      end

      if old.start_with?("http")   # if a standard full msg_id
        # just swap out the host
        parts = old.split('/q/', 2)
        "http://#{new}/q/#{parts[1]}"
      else                         # if just a queue name
        # just add the host
        "http://#{new}/q/#{old}"
      end
    end

    def self.process_pathname(path, verbose=false)
      rules = []
      begin
        lines = []
        File.open(path) do |f|
          lines = f.readlines
        end

        in_rule = false
        rule = nil
        lines.each_with_index do |line, i|
          i = i + 1   # i is offset by 0, so we bump it up for human readable line #s

          next if line[0..1] == "#"

          if in_rule
            if line[0..1] == "\n"
              rule.end_rule
              in_rule = false
              next
            end
            rule.process(line, i, verbose)
          end
          if line[0..4] == "rule "
            rule.end_rule if in_rule
            in_rule = true
            rule = Rule.new()
            rule.data[:num] = rules.length + 1
            rules << rule
            rule.process(line, i, verbose)
          end
        end
      rescue Errno::ENOENT => ex
        return nil
      rescue StandardError => ex
        if verbose
          p ex
          p ex.class
          p ex.backtrace
          puts ex
          puts ex.message
        end
        return nil
      end

      any_defaults,rules = rules.partition {|o| o.data[:desc] == 'default'}

      default_rule = Rule.new
      default_rule.rule('default')
      default_rule.action(:err)
      default_rule.end_rule()

      any_defaults.unshift(default_rule)

      rules << any_defaults.last

      RuleProcessor.new(rules)
    end

  end

end
