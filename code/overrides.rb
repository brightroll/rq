module RQ
  class Overrides

    attr_accessor :data

    def initialize(name, read_file = true)
      @data = {}
      path = "./queue/#{name}/form.json"
      get_json(path) if read_file
    end

    def get_json(path)
      if File.exist? path
        begin
          @data = JSON.parse(File.read(path))
        rescue
          throw :halt, [500, "500 - Bad overrides file"]
        end
      end
    end

    def show_field(name)
      if @data['default'] == "hidden" && @data[name] == nil
        false
      else
        true
      end
    end

    def text(field, what, default)
      if @data[field] && @data[field][what]
        return @data[field][what]
      end
      default
    end
  end
end
