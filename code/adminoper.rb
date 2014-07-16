module RQ
  class AdminOper

    attr_accessor :status

    def initialize(pathname)
      @pathname = pathname
      @dirname = File.dirname(pathname)
      @filename = File.basename(pathname)
      raise ArgumentError, "#{@dirname} doesn't exist" unless File.directory? @dirname

      @down_name = @dirname + "/" + @filename + ".down"
      @pause_name = @dirname + "/" + @filename + ".pause"

      @status = "UNKNOWN"
      @daemon_status = "UP"
    end

    def update!
      if File.exists?(@down_name)
        @status = "DOWN"
      elsif File.exists?(@pause_name)
        @status = "PAUSE"
      else
        @status = "UP"
      end
      update_status
    end

    # What the administrator cannot set, only daemons should set this 
    def set_daemon_status(stat)
      @daemon_status = stat

      update_status
    end

    private

    def update_status
      @status = @daemon_status if @daemon_status != "UP"
    end

  end
end
