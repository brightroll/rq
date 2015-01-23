module RQ
  class AdminOper

    attr_reader :admin_status
    attr_reader :oper_status

    def initialize(dirname, filename)
      raise ArgumentError, "#{dirname} doesn't exist" unless File.directory? dirname

      @down_file = File.join(dirname, filename + '.down')
      @pause_file = File.join(dirname, filename + '.pause')

      @oper_status = 'UP'
      update!
    end

    # Combined admin/oper status report
    def status
      @oper_status != 'UP' ? @oper_status : @admin_status
    end

    def update!
      if File.exist?(@down_file)
        @admin_status = 'DOWN'
      elsif File.exist?(@pause_file)
        @admin_status = 'PAUSE'
      else
        @admin_status = 'UP'
      end
    end

    def set_admin_status(stat)
      success = case stat
      when 'UP'
        delete_file(@down_file)
      when 'DOWN'
        create_file(@down_file)
      when 'PAUSE'
        create_file(@pause_file)
      when 'RESUME'
        delete_file(@pause_file)
      end

      # Change internal state based on file changes
      update!

      # Return success/failure of file change actions
      success
    end

    def set_oper_status(stat)
      @oper_status = stat
    end

    private

    def create_file(file)
      unless File.exist?(file)
        File.new(file, File::CREAT, 0644) rescue nil
      else
        true
      end
    end

    def delete_file(file)
      if File.exist?(file)
        count = File.unlink(file) rescue 0
        count > 0
      else
        true
      end
    end

  end
end
