# unixrack - ruby webserver compatible with rack using unix philosophy 
#
# license  - see COPYING 

require 'rack/content_length'
require 'time'
require 'stringio'


# Thx - Logan Capaldo 
require 'dl/import'
module Alarm
  extend DL::Importable
  if RUBY_PLATFORM =~ /darwin/
    so_ext = 'dylib'
  else
    so_ext = 'so.6'
  end
  dlload "libc.#{so_ext}"
  extern "unsigned int alarm(unsigned int)"
end

module UnixRack
  class Socket

    attr_accessor :hdr_method, :headers

    def initialize(sock)
      @sock = sock
      @buff = ""
    end

    def peeraddr
      @sock.peeraddr
    end

    def self.write_buff(io, buff)
      len = buff.length
      nwritten = 0

      out_buff = buff

      while true
        nw = io.syswrite(out_buff)
        nwritten = nwritten + nw
        break if nw == out_buff.length
        out_buff = out_buff.slice(nw..-1)
      end
      nwritten
    end

    def self.read_sock_num_bytes(sock, num, log = lambda {|x| x})
      retval = [false, '']
      buff = ""
      num_left = num
      while true
        begin
          #log("PRE Doing sysread")
          numr = num_left < 32768 ? num_left : 32768
          dat = sock.sysread(numr)
          #log("Doing sysread #{dat.inspect}")
          buff = buff + dat
          if buff.length == num
            retval = [true, buff]
            break
          else
            num_left = num_left - dat.length
          end
        rescue Errno::EINTR  # Ruby threading can cause an alarm/timer interrupt on a syscall
          retry
        rescue EOFError
          retval = [false, "EOF", buff]
          break
        rescue EOFError,Errno::ECONNRESET,Errno::EPIPE,Errno::EINVAL,Errno::EBADF
          retval = [false, "Exception occurred on socket read"]
          #log("Got an #{$!} from socket read")
          break
        end
      end
      retval
    end


    def error_reply(num, txt)
      puts "#{$$}: Error: #{num} #{txt}"
      $stdout.flush

      bod = [
      "<!DOCTYPE HTML PUBLIC \"-//IETF//DTD HTML 2.0//EN\">",
      "<html><head>",
      "<title>#{num} #{txt}</title>",
      "</head><body>",
      "<h1>#{num} - #{txt}</h1>",
      "<hr>",
      "</body></html>",
      ]

      bod_txt = bod.join("\r\n")

      hdr = [
      "HTTP/1.1 #{num} #{txt}",
      "Date: #{Time.now.httpdate}",
      "Server: UnixRack",
      "Content-Length: #{bod_txt.length}",
      "Connection: close",
      "Content-Type: text/html; charset=iso-8859-1",
      ]

      hdr_txt = hdr.join("\r\n")

      res = hdr_txt + "\r\n\r\n" + bod_txt

      Socket.write_buff(@sock, res)

      exit! 0
    end

    def do_read
      begin
        dat = @sock.sysread(16384)
      rescue Errno::EINTR  # Ruby threading can cause an alarm/timer interrupt on a syscall
        retry
      rescue EOFError
        puts "#{$$}: Got an EOF from socket read"
        $stdout.flush
        return nil
      rescue EOFError,Errno::ECONNRESET,Errno::EPIPE,Errno::EINVAL,Errno::EBADF
        puts "#{$$}: Got an #{$!} from socket read"
        $stdout.flush
        exit! 0
      end
      @buff = @buff + dat
      return @buff
    end

    def read_content
      cont_len = @headers['Content-Length'].to_i

      #if cont_len < (8 * 1024 * 1024)
      if cont_len < (1024 * 1024)
        # Small file, just use mem
        while true
          if @buff.length == cont_len
            f = StringIO.new(@buff)
            @buff = ""
            return f
          end
          return nil if not do_read
        end
      else
        # Large file, use disk
        f = nil
        tmpname = "./.__tmp__unixrack_upload__#{$$}.tmp"
        begin
          tmpfd = IO.sysopen(tmpname, File::RDWR | File::CREAT | File::EXCL, 0600)
          f = IO.new(tmpfd, "w+")
          File.unlink(tmpname)
        rescue
          p $!
          $stdout.flush
          return nil
        end

        # Write what we already have
        len = @buff.length
        if len > 0
          f.syswrite(@buff)
          @buff = ""
        end

        while true
          return f if len == cont_len

          return nil if not do_read

          len += @buff.length
          f.syswrite(@buff)
          @buff = ""
        end
      end
    end

    def read_headers
      while true
        r = do_read
        break if @buff.index "\r\n\r\n"
        error_reply(400, "Bad Request") if r == nil
      end

      a, b = @buff.split("\r\n\r\n", 2)

      @buff = b
      @hdr_buff = a
      @hdr_lines = @hdr_buff.split("\r\n")

      @hdr_method_line = @hdr_lines[0]
      @hdr_method = @hdr_method_line.split(" ")

      @hdr_field_lines = @hdr_lines.slice(1..-1)   # would prefer first, and rest
      @headers = @hdr_field_lines.inject( {} ) { |h, line| k,v = line.split(": "); h[k] = v; h }
    end

    def send_response(status, headers, body)
      out = []

      msg = Rack::Utils::HTTP_STATUS_CODES[status.to_i]

      puts "#{$$}: Response: #{status} #{msg}"
      $stdout.flush
      hdr_ary = [ "HTTP/1.0 #{status} #{msg}" ]

      headers['Connection'] ||= 'close'

      headers.each do
        |k,vs|
        vs.split("\n").each { |v| hdr_ary << [ "#{k}: #{v}" ] }
      end

      hdr = hdr_ary.join("\r\n")

      out = [ hdr, "\r\n\r\n" ]

      body.each { |part| out << part.to_s }

      out_buff = out.join("")

      Socket.write_buff(@sock, out_buff)
    end

  end
end

module Rack
  module Handler
    class UnixRack

      def self.run(app, options={})

        require 'socket'
        port = options[:port] || 8080
        host = options[:host] || '127.0.0.1'
        listen = options[:listen] || '127.0.0.1'
        allowed_ips = options[:allowed_ips] || []
        server = TCPServer.new(listen, port)

        trap(:CHLD) do
          begin
            while true
              pid, status = Process.waitpid2(-1, Process::WNOHANG)
              if pid == nil
                break
              end
              puts "#{pid}: exited - status #{status}"
              $stdout.flush
            end
          rescue Errno::ECHILD
          end
        end

        trap(:TERM) { puts "#{$$}: Listener received TERM. Exiting."; $stdout.flush; exit! 0  }
        trap("SIGINT") { puts "#{$$}: Listener received INT. Exiting."; $stdout.flush; exit! 0  }

        while true
          begin
            conn = server.accept
          rescue Errno::EAGAIN, Errno::ECONNABORTED
            p "Connection interrupted on accept"
            $stdout.flush
            next
          rescue
            p "DRU"
            p $!
            $stdout.flush
            exit
          end

          pid = fork

          if pid == nil
            # We are in child
            server.close
            trap("ALRM") { puts "#{$$}: Child took too long. Goodbye"; $stdout.flush; exit! 2  }
            trap(:TERM)  { puts "#{$$}: TERM. Time to go... Goodbye"; $stdout.flush; exit! 0  }

            puts "#{$$}: child started"
            $stdout.flush

            Alarm.alarm(5)                # if no command received in 5 secs

            sock = ::UnixRack::Socket.new(conn)

            sock.read_headers()
            puts "#{$$}: Request: #{sock.hdr_method.inspect}"
            $stdout.flush
            Alarm.alarm(60)               # if command not handled in 60 seconds 

            client_ip = sock.peeraddr.last

            if not allowed_ips.empty?
              if not (allowed_ips.any? { |e| client_ip.include? e })
                sock.error_reply(403, "Forbidden")
              end
            end

            if ["GET", "POST"].include?(sock.hdr_method[0])

              env = {}

              if sock.hdr_method[0] == "GET"
                content = StringIO.new("")
              elsif sock.hdr_method[0] == "POST"
                if not sock.headers.include?('Content-Length')
                  sock.error_reply(400, "Bad Request no content-length")
                end
                if not sock.headers.include?('Content-Type')
                  sock.error_reply(400, "Bad Request no content-type")
                end

                env["CONTENT_LENGTH"] = sock.headers['Content-Length']
                env["CONTENT_TYPE"] = sock.headers['Content-Type']

                # F the 1.1
                if sock.headers.include?('Expect')
                  sock.error_reply(417, "Expectation Failed")
                end

                # It is required that we read all of the content prior to responding
                content = sock.read_content

                if content == nil
                  sock.error_reply(400, "Bad Request not enough content")
                end
              end

              app = ContentLength.new(app)


              env["REQUEST_METHOD"] = sock.hdr_method[0]

              uri_parts = sock.hdr_method[1].split("?", 2)
              if uri_parts.length != 2
                uri_parts << ""
              end

              # If somebody wants to send me the big absoluteURI...
              # fine... what is wasting a few more cycles to chop it off
              if uri_parts[0].index('http://') == 0
                uri_parts[0] = uri_parts[0].sub(/http:\/\/[^\/]+/, '')
              end

              env["SCRIPT_NAME"] = uri_parts[0]
              env["PATH_INFO"] = uri_parts[0]
              env["QUERY_STRING"] = uri_parts[1]

              env["SERVER_NAME"] = host
              env["SERVER_PORT"] = port
              env["REMOTE_ADDR"] = client_ip

              env["HTTP_VERSION"] = "HTTP/1.1"
              if sock.headers['If-Modified-Since']
                env["HTTP_IF_MODIFIED_SINCE"] = sock.headers['If-Modified-Since']
              end

              env.update({"rack.version" => [1,1],
                         "rack.input" => content,
                         "rack.errors" => $stderr,
                         "rack.multithread" => false,
                         "rack.multiprocess" => true,
                         "rack.run_once" => true,
                         "rack.url_scheme" => "http"
              })

              status, headers, body = app.call(env)

              sock.send_response(status, headers, body)

              conn.close
              exit! 0
            end

            sock.error_reply(500, "Server Error")
            conn.close
            exit! 0
          end
          # We are in parent
          conn.close
        end
      end

      def old_debug
        # Old Debug Codes
        conn.print "HTTP/1.1 200/OK\r\nContent-type: text/html\r\n\r\n"
        conn.print "<html><body><h1>#{Time.now}</h1>\r\n"
        conn.print "<ul>\r\n"
        conn.print "<li>#{RUBY_PLATFORM}</li>\r\n"
        ENV.keys.sort.each do
          |k|
          conn.print "<li>#{k} - #{ENV[k]}</li>\r\n"
        end
        conn.print "</ul>\r\n"

        conn.print "<ul>\r\n"
        conn.print "<li>#{sock.hdr_method.inspect}</li>\r\n"
        sock.headers.keys.sort.each do
          |k|
          conn.print "<li>#{k} - #{sock.headers[k]}</li>\r\n"
        end
        conn.print "</ul>\r\n"

        conn.print "</body></html>\r\n"
        conn.close
        exit! 0
      end

    end
  end
end
