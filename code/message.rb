require 'socket'
require 'json'

module RQ
  class Message < Struct.new(:msg_id, :status, :dest, :src, :param1, :param2, :param3, :param4)

    def initialize(options={})
    end

    def init_with_opts(options)
      #"dest"=>"http://localhost:3333/queue/", "src"=>"dru", "param1"=>"test", "param2"=>"", "param3"=>"", "param4"=>"", "status"=>"ready"
      @status = options["status"]
      @dest = options["dest"]
      @src = options["src"]
      @param1 = options["param1"]
      @param2 = options["param2"]
      @param3 = options["param3"]
      @param4 = options["param4"]
    end

  end
end
