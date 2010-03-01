require 'rack/content_length'
require 'time'

# Thx - Logan Capaldo 
require 'dl/import'
module Alarm
  extend DL::Importable
  if RUBY_PLATFORM =~ /darwin/
    so_ext = 'dylib'
  else
    so_ext = 'so'
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

    def write_buff(io, buff)
      len = buff.length
      nwritten = 0

      out_buff = buff.dup

      while true
        nw = io.syswrite(out_buff)
        break if new = out_buff.length
        out_buff = out_buff.slice(nw..-1)
      end
    end

    def error_reply(num, txt)
      puts "Error: #{num} #{txt}"

      bod_txt = <<-END
      <!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN">
      <html><head>
      <title>#{num} #{txt}</title>
      </head><body>
      <h1>#{txt}</h1>
      <hr>
      </body></html>
      END

      hdr_txt = <<-END
      HTTP/1.1 #{num} #{txt}
      Date: #{Time.now.httpdate}
      Server: UnixRack
      Content-Length: #{bod_txt.length}
      Connection: close
      Content-Type: text/html; charset=iso-8859-1
      END

      res = hdr_txt + bod_txt

      write_buff(@sock, res)

      exit! 0
    end

    def do_read
      begin
        dat = @sock.sysread(16384)
      rescue EOFError
        puts "Got an EOF from socket read"
        return nil
      rescue EOFError,Errno::ECONNRESET,Errno::EPIPE,Errno::EINVAL,Errno::EBADF
        puts "Got an #{$!} from socket read"
        exit! 0
      end
      @buff = @buff + dat
      return @buff
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

      write_buff(@sock, out_buff)
    end

  end
end

module Rack
  module Handler
    class UnixRack

      def self.run(app, options=nil)

        require 'socket'
        port = options[:port] || 8080
        host = options[:host] || '127.0.0.1'
        server = TCPServer.new(host, port)

        trap(:CHLD) do
          begin
            while true
              pid, status = Process.waitpid2(-1, Process::WNOHANG)
              if pid == nil
                break
              end
              puts "UR pid #{pid} status #{status} exited"
            end
          rescue Errno::ECHILD
          end
        end

        trap(:TERM) { puts "Listener received TERM. Exiting."; exit! 0  }
        trap("SIGINT") { puts "Listener received INT. Exiting."; exit! 0  }

        while true
          begin
            conn = server.accept
          rescue Errno::EAGAIN, Errno::ECONNABORTED
            p "Connection interrupted on accept"
            next
          rescue
            p "DRU"
            p $!
            exit
          end

          pid = fork

          if pid == nil
            server.close
            trap("ALRM") { p "Child took too long. Goodbye"; exit! 2  }
            trap(:TERM)  { p "TERM. Time to go... Goodbye"; exit! 0  }

            Alarm.alarm(5)                # if no command received in 5 secs

            sock = ::UnixRack::Socket.new(conn)

            sock.read_headers()
            puts "Request: #{sock.hdr_method.inspect}"
            Alarm.alarm(60)               # if command not handled in 60 seconds 

            if sock.hdr_method[0] == "GET"
              # setup env for RACK
              #serve app
              #p app

              app = ContentLength.new(app)

              env = {}

              env["REQUEST_METHOD"] = sock.hdr_method[0]

              uri_parts = sock.hdr_method[1].split("?", 2)
              if uri_parts.length != 2
                uri_parts << ""
              end

              env["SCRIPT_NAME"] = uri_parts[0]
              env["PATH_INFO"] = uri_parts[0]
              env["QUERY_STRING"] = uri_parts[1]

              env["SERVER_NAME"] = host
              env["SERVER_PORT"] = port

              env["HTTP_VERSION"] = "HTTP/1.1"
              if sock.headers['If-Modified-Since']
                env["HTTP_IF_MODIFIED_SINCE"] = sock.headers['If-Modified-Since']
              end

              #p env

              env.update({"rack.version" => [1,1],
                          "rack.input" => StringIO.new(""),
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

            conn.close
            exit! 0

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
            #serve app
            exit! 0
          end

          conn.close
        end

      end

      def self.serve(app)
        app = ContentLength.new(app)

        env = ENV.to_hash
        env.delete "HTTP_CONTENT_LENGTH"

        env["SCRIPT_NAME"] = ""  if env["SCRIPT_NAME"] == "/"

        env.update({"rack.version" => [0,1],
                     "rack.input" => $stdin,
                     "rack.errors" => $stderr,

                     "rack.multithread" => false,
                     "rack.multiprocess" => true,
                     "rack.run_once" => true,

                     "rack.url_scheme" => ["yes", "on", "1"].include?(ENV["HTTPS"]) ? "https" : "http"
                   })

        env["QUERY_STRING"] ||= ""
        env["HTTP_VERSION"] ||= env["SERVER_PROTOCOL"]
        env["REQUEST_PATH"] ||= "/"

        status, headers, body = app.call(env)
        begin
          send_headers status, headers
          send_body body
        ensure
          body.close  if body.respond_to? :close
        end
      end

      def self.old_send_headers(status, headers)
        STDOUT.print "Status: #{status}\r\n"
        headers.each { |k, vs|
          vs.split("\n").each { |v|
            STDOUT.print "#{k}: #{v}\r\n"
          }
        }
        STDOUT.print "\r\n"
        STDOUT.flush
      end

      def self.old_send_headers(status, headers)
        STDOUT.print "Status: #{status}\r\n"
        headers.each { |k, vs|
          vs.split("\n").each { |v|
            STDOUT.print "#{k}: #{v}\r\n"
          }
        }
        STDOUT.print "\r\n"
        STDOUT.flush
      end

      def self.old_send_body(body)
        body.each { |part|
          STDOUT.print part
          STDOUT.flush
        }
      end
    end
  end
end
