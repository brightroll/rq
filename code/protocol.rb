require 'unixrack'

# Mix the Protocol module into classes that communicate on internal sockets

module RQ
  module Protocol
    def set_protocol_sock_path(sock_path)
      @protocol_sock_path = sock_path
    end

    def read_packet(sock)
      protocol = do_read(sock, 4)

      if protocol != 'rq1 '
        log("REQ - Invalid protocol - bad ver")
        return nil
      end

      size_str = do_read(sock, 9)

      if size_str[-1..-1] != " "
        log("REQ - Invalid protocol - bad size #{size_str}")
        return nil
      end

      size = size_str.to_i
      log("REQ - size #{size}")

      result = UnixRack::Socket.read_sock_num_bytes(sock, size)

      if result[0] == false
        log("REQ - Invalid packet - didn't receive contents")
        return nil
      end

      result[1]
    end

    def send_packet(sock, resp)
      log_msg = resp.length > 80 ? "#{resp[0...80]}..." : resp
      log("RESP [ #{resp.length}  #{log_msg} ]")
      sock_msg = sprintf("rq1 %08d %s", resp.length, resp)
      UnixRack::Socket.write_buff(sock, sock_msg)
      sock.close
    end

    # msg is single word, data is assumbed to be content as json
    def send_recv(msg, data="")
      client = UNIXSocket.open(@protocol_sock_path)

      contents = "#{msg} #{data}"
      sock_msg = sprintf("rq1 %08d %s", contents.length, contents)

      UnixRack::Socket.write_buff(client, sock_msg)

      protocol = do_read(client, 4)

      if protocol != 'rq1 '
        raise "Invalid Protocol - Expecting 'rq1 ' got: #{protocol}"
      end

      size_str = do_read(client, 9)

      if size_str[-1..-1] != " "
        raise "Invalid Protocol"
      end

      size = size_str.to_i

      result = UnixRack::Socket.read_sock_num_bytes(client, size, lambda {|s| puts s})

      if result[0] == false
        return ["fail", result[1]]
      end

      client.close

      JSON.parse(result[1])
    rescue SocketError => e
      $stderr.puts "Error on the socket: #{e}"
      nil
    end

    private

    def do_read(client, numr = 32768)
      begin
        dat = client.sysread(numr)
      rescue Errno::EINTR  # Ruby threading can cause an alarm/timer interrupt on a syscall
        sleep 0.001 # A tiny pause to prevent consuming all CPU
        retry
      rescue EOFError
        #TODO: add debug mode
        #puts "Got an EOF from socket read"
        return nil
      rescue Errno::ECONNRESET,Errno::EPIPE,Errno::EINVAL,Errno::EBADF
        raise "Got an #{$!} from socket read"
      end
      dat
    end

  end
end
