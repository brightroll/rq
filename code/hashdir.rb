module RQ
  class HashDir

    # For now, the system is not configurable in terms of pattern match or depth

    def self.make(path)
      FileUtils.mkdir_p(path)
      return true
    end

    def self.exist(path, msg_id)
      parts = self.msg_id_parts(msg_id)
      # parts = [ "YYYYmmDD", "HH", "MM" ]

      # If we got bad data, return false
      return false unless parts

      File.exists?("#{path}/#{parts[0]}/#{parts[1]}/#{parts[2]}/#{msg_id}")
    end

    # Do a DFT traverse in reverse order so most
    # recent is first
    def self.entries(path, limit = nil)
      self.entries_int(path, 0, [], limit)
    end

    def self.entries_int(path, level, accum, limit = nil)
      if level == 0
        # YYYYMMDD
        ents1 = Dir.glob("#{path}/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]")
        ents1.sort.reverse.each {
          |e|
          self.entries_int(e, 1, accum, limit)
          break if limit && accum.length == limit
        }
      elsif level == 1
        # HH
        ents1 = Dir.glob("#{path}/[0-9][0-9]")
        ents1.sort.reverse.each {
          |e|
          self.entries_int(e, 2, accum, limit)
          break if limit && accum.length == limit
        }
      elsif level == 2
        # MM
        ents1 = Dir.glob("#{path}/[0-9][0-9]")
        ents1.sort.reverse.each {
          |e|
          self.entries_int(e, 3, accum, limit)
          break if limit && accum.length == limit
        }
      elsif level == 3
        # MESG-ID
        ents1 = Dir.glob("#{path}/[0-9][0-9]*")
        ents1.sort.reverse.each {
          |e|
          accum << e.split('/').last
          break if limit && accum.length == limit
        }
      end
      accum
    end

    def self.entries_old(path, limit = nil)
      # Do a depth first walk of the path to get the message ids
      ents1 = Dir.glob("#{path}/**/msg")
      # we want the msg_id part (-2), just before last (-1)
      ents2 = ents1.map { |e| e.split('/')[-2] }
    end

    def self.num_entries(path)
      self.num_entries_int(path, 0)
    end

    def self.num_entries_int(path, level)
      sum = 0
      if level == 0
        # YYYYMMDD
        ents1 = Dir.glob("#{path}/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]")
        ents1.sort.reverse.each {
          |e|
          sum += self.num_entries_int(e, 1)
        }
      elsif level == 1
        # HH
        ents1 = Dir.glob("#{path}/[0-9][0-9]")
        ents1.sort.reverse.each {
          |e|
          sum += self.num_entries_int(e, 2)
        }
      elsif level == 2
        # MM
        ents1 = Dir.glob("#{path}/[0-9][0-9]")
        ents1.sort.reverse.each {
          |e|
          sum += self.num_entries_int(e, 3)
        }
      elsif level == 3
        # MESG-ID
        ents1 = Dir.glob("#{path}/[0-9][0-9]*")
        sum += ents1.length
      end
      sum
    end

    def self.num_entries_old(path)
      # Do a depth first walk of the path to get the message ids
      ents1 = Dir.glob("#{path}/**/msg")
      ents1.length
    end


    def self.inject(prev_msg_path, new_base_path, msg_id)
      parts = self.msg_id_parts(msg_id)
      FileUtils.mkdir_p("#{new_base_path}/#{parts[0]}/#{parts[1]}/#{parts[2]}")
      newname = "#{new_base_path}/#{parts[0]}/#{parts[1]}/#{parts[2]}/#{msg_id}"
      File.rename(prev_msg_path, newname)
    end

    def self.path_for(que_base_path, msg_id)
      parts = self.msg_id_parts(msg_id)
      "#{que_base_path}/#{parts[0]}/#{parts[1]}/#{parts[2]}/#{msg_id}"
    end

    def self.msg_id_parts(msg_id)
      # Ex. msg_id 20100625.0127.35.122.7509656
      if msg_id =~ /(\d\d\d\d\d\d\d\d)\.(\d\d)(\d\d)/
        [$1, $2, $3]
      else
        nil
      end
    end

  end
end
