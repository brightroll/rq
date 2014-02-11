require 'vendor/environment'
require 'json'

module RQ
  class JSONConfigFile
    # A class to keep an eye on a config file and determine
    # if it was reloaded in order to cause any observers to adjust

    # stat = File.stat(@queue_path + "/prep/" + name)

    attr_accessor :path
    attr_accessor :conf

    NO_CHANGE     = 0
    CHANGED       = 1
    ERROR_IGNORED = 2

    def initialize(path)
      @path = path
      @stat = File.stat(@path) rescue nil
      load_config
    end

    def load_config
      @conf = JSON.parse(File.read(@path))
      true
    rescue
      false
    end

    def check_for_change
      stat = File.stat(@path)
      if !@stat || (stat.ino != @stat.ino || stat.mtime != @stat.mtime)
        if load_config
          @stat = stat
          CHANGED
        else
          ERROR_IGNORED
        end
      else
        NO_CHANGE
      end
    rescue
      ERROR_IGNORED
    end
  end
end
