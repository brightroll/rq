

module RQ
  class AdminOper

    attr_accessor :admin_status
    attr_accessor :oper_status

    def initialize(pathname)
      @pathname = pathname
      @dirname = File.dirname(pathname)
      @filename = File.basename(pathname)
      raise ArgumentError, "#{@dirname} doesn't exist" unless File.directory? @dirname

      @down_name = @dirname + "/" + @filename + ".down"
      @pause_name = @dirname + "/" + @filename + ".pause"

      @admin_status = "UNKNOWN"
      @oper_status = "UNKNOWN"
      @daemon_status = "UP"
    end

    def update!
      if File.exists?(@down_name)
        @admin_status = @oper_status = "DOWN"
      elsif File.exists?(@pause_name)
        @admin_status = @oper_status = "PAUSE"
      else
        @admin_status = @oper_status = "UP"
      end
      update_status
    end

    # What the administrator cannot set, only daemons should set this 
    def set_daemon_status(stat)
      @daemon_status = stat

      update_status
    end

    def update_status
      if @daemon_status == "UP"
        @oper_status = @admin_status
      else
        @oper_status = @daemon_status
      end
    end
    private :update_status

  end
end

