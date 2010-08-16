

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

      File.exists?("#{path}/#{parts[0]}/#{parts[1]}/#{parts[2]}/#{msg_id}")
    end
    
    def self.entries(path)
      # Do a depth first walk of the path to get the message ids
      ents1 = Dir.glob("#{path}/**/msg")
      # we want the msg_id part (-2), just before last (-1)
      ents2 = ents1.map { |e| e.split('/')[-2] }
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

