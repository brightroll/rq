require 'socket'
require 'fcntl'

# Mix the Protocol module into classes that communicate on internal sockets

module RQ
  module Protocol
    def set_protocol_sock_path(sock_path)
      @protocol_sock_path = sock_path
    end

    def set_protocol_messages(messages)
      @protocol_messages = messages
    end

    def set_nonblocking(sock)
      flag = File::NONBLOCK
      if defined?(Fcntl::F_GETFL)
        flag |= sock.fcntl(Fcntl::F_GETFL)
      end
      sock.fcntl(Fcntl::F_SETFL, flag)
    end

    def reset_nonblocking(sock)
      # Linux Doesn't inherit and BSD does... recomended behavior is to set again
      flag = 0xffffffff ^ File::NONBLOCK
      if defined?(Fcntl::F_GETFL)
        flag &= sock.fcntl(Fcntl::F_GETFL)
      end
      sock.fcntl(Fcntl::F_SETFL, flag)
    end

    def read_packet(sock)
      protocol = do_read(sock, 4)

      if protocol != "rq1 "
        raise "REQ - Invalid protocol - bad ver #{protocol}"
      end

      size_str = do_read(sock, 9)

      if size_str[-1..-1] != " "
        raise "REQ - Invalid protocol - bad size #{size_str}"
      end

      size = size_str.to_i
      $log.debug("REQ - size #{size}")

      do_read(sock, size)
    end

    def send_packet(sock, resp)
      log_msg = resp.length > 80 ? "#{resp[0...80]}..." : resp
      $log.debug("RESP [ #{resp.bytesize}  #{log_msg} ]")
      sock_msg = sprintf("rq1 %08d %s", resp.bytesize, resp)
      do_write(sock, sock_msg)
    end

    # msg is single word, data is assumbed to be content as json
    def send_recv(msg, data="")
      client = UNIXSocket.open(@protocol_sock_path)

      send_packet(client, "#{msg} #{data}")
      reply = read_packet(client) rescue nil

      client.close

      JSON.parse(reply) if reply
    rescue
      $log.warn("Error on the socket: #{$!} [ #{$@} ]")
      nil
    end

    private

    # Borrowed from UnixRack and updated by Backports
    def do_write(client, buff)
      lwritten = client.syswrite(buff)
      nwritten = lwritten

      # Only dup the original buff if we didn't get it all in the first try
      while nwritten < buff.bytesize
        remaining = buff.bytesize - nwritten
        rbuff = (rbuff || buff).unpack("@#{lwritten}a#{remaining}").first
        lwritten = client.syswrite(rbuff)
        nwritten += lwritten
      end

      nwritten
    rescue
      defined?(nwritten) ? nwritten : 0
    end

    def do_read(client, numr = 32768)
      client.sysread(numr)
    rescue Errno::EAGAIN, Errno::EINTR  # Ruby threading can cause an alarm/timer interrupt on a syscall
      sleep 0.001 # A tiny pause to prevent consuming all CPU
      retry
    rescue EOFError
      $log.debug("Got an EOF from socket read")
      return nil
    rescue Errno::ECONNRESET,Errno::EPIPE,Errno::EINVAL,Errno::EBADF
      raise "Got an #{$!} from socket read"
    end

    def message_send_recv(name, *params)
      param = params.first
      case param
      when nil
        send_recv(name)
      when String
        send_recv(name, param)
      else
        send_recv(name, param.to_json)
      end
    end

    # Provides magic methods for words in the @protocol_messages array
    def method_missing(name, *args, &block)
      if @protocol_messages && @protocol_messages.include?(name.to_s)
        message_send_recv(name, *args, &block)
      else
        super # You *must* call super if you don't handle the
              # method, otherwise you'll mess up Ruby's method
              # lookup.
      end
    end

  end
end
