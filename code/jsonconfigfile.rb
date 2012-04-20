require 'json'

module RQ
  class JSONConfigFile

    # A class to keep an eye on a config file and determine
    # if it was reloaded in order to cause any observers to adjust

    #stat = File.stat(@queue_path + "/prep/" + name)

    attr_accessor :path
    attr_accessor :conf

    NO_CHANGE     = 0
    CHANGED       = 1
    ERROR_IGNORED = 2

    def initialize(path)
      @path = path
    end

    def load_config
      begin
        data = File.read(@path)
        js_data = JSON.parse(data)
        @conf = js_data
        @stat = File.stat(@path)
      rescue
        return nil
      end
      self
    end

    def check_for_change
      begin
        stat = File.stat(@path)
        if (stat.ino != @stat.ino) || (stat.mtime != @stat.mtime)
          load_config ? CHANGED : ERROR_IGNORED
        else
          NO_CHANGE
        end
      rescue
        ERROR_IGNORED
      end
    end
  end
end

