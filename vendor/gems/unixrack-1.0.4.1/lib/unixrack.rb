require "unixrack/version"

# unixrack - ruby webserver compatible with rack using old unix style
#
# license  - see COPYING

require 'rack/content_length'
if not Rack.const_defined?("Handler")
  require 'rack/handler'
end
require 'time'
require 'socket'
require 'stringio'

module UnixRack

  module Alarm
    # Thx - Logan Capaldo
    case RUBY_VERSION.to_f
    when 1.8
      require 'dl/import'
      extend DL::Importable
    when 1.9
      require 'dl/import'
      extend DL::Importer
    else # 2.0+
      require 'fiddle/import'
      extend Fiddle::Importer
    end
    if RUBY_PLATFORM =~ /darwin/
      so_ext = 'dylib'
    else
      so_ext = 'so.6'
    end
    dlload "libc.#{so_ext}"
    extern "unsigned int alarm(unsigned int)"
  end

  class Socket

    attr_accessor :hdr_method, :headers
    attr_accessor :sock

    def initialize(sock)
      TCPSocket.do_not_reverse_lookup = true
      @sock = sock
      @buff = ""
    end

    def peeraddr
      @sock.peeraddr
    end

    def self.write_buff(io, buff)
      nwritten = 0

      out_buff = buff

      # buff could be UTF-8
      while true
        nw = io.syswrite(out_buff)
        nwritten = nwritten + nw
        break if nw == out_buff.bytesize
        out_buff = out_buff.byteslice(nw..-1)
      end
      nwritten
    end

    def self.close(io)
      io.close
    end

    def self.read_sock_num_bytes(sock, num, log = lambda { |x| x })
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
        rescue Errno::EINTR # Ruby threading can cause an alarm/timer interrupt on a syscall
          retry
        rescue EOFError
          retval = [false, "EOF", buff]
          break
        rescue Errno::ECONNRESET, Errno::EPIPE, Errno::EINVAL, Errno::EBADF
          retval = [false, "Exception occurred on socket read"]
          #log("Got an #{$!} from socket read")
          break
        end
      end
      retval
    end


    def do_read
      begin
        dat = @sock.sysread(16384)
      rescue Errno::EINTR # Ruby threading can cause an alarm/timer interrupt on a syscall
        retry
      rescue EOFError
        puts "#{$$}: Got an EOF from socket read"
        $stdout.flush
        return nil
      rescue Errno::ECONNRESET, Errno::EPIPE, Errno::EINVAL, Errno::EBADF
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
          if len == cont_len
            f.rewind
            return f
          end

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
        return false if r == nil
      end

      a, b = @buff.split("\r\n\r\n", 2)

      @buff = b
      @hdr_buff = a
      @hdr_lines = @hdr_buff.split("\r\n")

      @hdr_method_line = @hdr_lines[0]
      @hdr_method = @hdr_method_line.split(" ")

      @hdr_field_lines = @hdr_lines.slice(1..-1) # would prefer first, and rest
      headers = @hdr_field_lines.inject({}) { |h, line| k, v = line.split(": "); h[k] = v; h }
      @headers = canonicalize_headers(headers)
      true
    end

    private

    def canonicalize_headers(headers)
      headers.keys.each do |key|
        headers[key.split(/-/).map(&:capitalize).join('-')] = headers.delete(key)
      end
      headers
    end
  end
end

module Rack
  module Handler
    class UnixRack

      @@chdir = ''
      @@client_ip = nil
      @@pid = nil
      @@start_time = Time.now

      # Set this in config.ru when in daemon mode
      # Why? It appears that the behaviour of most servers
      # is to expect to be in a certain dir when run
      # Or, another way, rackup daemon mode is a bit strict
      # and does the old-school chdir to '/' as a daemon.
      # the fact is people probably don't use rackup often
      def self.set_chdir(dir)
        @@chdir = dir
      end

      def self.log(response_code, message='-', method='-', url='-', options={})
        return
        #TODO: Ignore the early return
        #TODO: I'm going to make this a config debug option, use your other middleware logging for now
        ip = @@client_ip || '-'
        now = Time.now
        duration = ((now.to_f - @@start_time.to_f) * 1000).to_i / 1000.0
        puts "#{now.strftime('%Y-%m-%dT%H:%M:%S%z')},#{@@pid},#{ip},#{sprintf("%0.03f", duration)},#{response_code},\"#{message}\",#{method},\"#{url}\""
        $stdout.flush
      end

      def self.send_error_response!(sock, num, txt, method, url)
        log(num, txt, method, url)

        bod = [
            "<!DOCTYPE HTML PUBLIC \"-//IETF//DTD HTML 2.0//EN\">",
            "<html><head>",
            "<title>#{num} #{txt}</title>",
            "</head><body>",
            "<h1>#{num} - #{txt}</h1>",
            "<hr>",
            "</body></html>"
        ]

        bod_txt = bod.join("\r\n")

        hdr = [
            "HTTP/1.1 #{num} #{txt}",
            "Date: #{@@start_time.httpdate}",
            "Server: UnixRack",
            "Content-Length: #{bod_txt.length}",
            "Connection: close",
            "Content-Type: text/html; charset=iso-8859-1"
        ]

        hdr_txt = hdr.join("\r\n")

        res = hdr_txt + "\r\n\r\n" + bod_txt

        ::UnixRack::Socket.write_buff(sock.sock, res)
        ::UnixRack::Socket.close(sock.sock)
        exit! 0
      end

      def self.send_response!(sock, status, method, url, headers, body)
        out = []

        msg = Rack::Utils::HTTP_STATUS_CODES[status.to_i]

        log(status, msg, method, url)

        hdr_ary = ["HTTP/1.1 #{status} #{msg}"]

        headers['Connection'] ||= 'close'

        headers.each do
        |k, vs|
          vs.split("\n").each { |v| hdr_ary << ["#{k}: #{v}"] }
        end

        hdr = hdr_ary.join("\r\n")

        out = [hdr, "\r\n\r\n"]

        body.each { |part| out << part.to_s }

        out_buff = out.join("")

        ::UnixRack::Socket.write_buff(sock.sock, out_buff)
        ::UnixRack::Socket.close(sock.sock)

        # Conforming to SPEC - I was noticing that Sinatra logging wasn't working
        body.close if body.respond_to? :close

        exit! 0
      end


      def self.run(app, options={})

        require 'socket'
        port = options[:Port] || 8080
        host = options[:Hostname] || 'localhost'
        listen = options[:Host] || '127.0.0.1'
        allowed_ips = options[:allowed_ips] || []
        server = TCPServer.new(listen, port)

        @@pid = $$
        trap(:CHLD) do
          begin
            while true
              pid, status = Process.waitpid2(-1, Process::WNOHANG)
              if pid == nil
                break
              end
              @@start_time = Time.now
              log(-(status.exitstatus), 'child exited non-zero') if status.exitstatus != 0
              #puts "#{pid}: exited - status #{status}"
              #$stdout.flush
            end
          rescue Errno::ECHILD
          end
        end

        trap(:TERM) { log(0, "Listener received TERM. Exiting."); exit! 0 }
        trap(:INT) { log(0, "Listener received INT. Exiting."); exit! 0 }

        if not @@chdir.empty?
          Dir.chdir @@chdir
        end
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
            p $!.backtrace
            $stdout.flush
            exit
          end

          pid = fork

          if pid != nil
            # We are in parent
            conn.close
          else
            # We are in child
            @@pid = $$
            server.close
            @@start_time = Time.now

            trap(:ALRM) { log(0, "Child received ALARM during read_headers. Exiting."); exit! 2 }
            trap(:TERM) { log(0, "Child received TERM. Exiting."); exit! 0 }

            ::UnixRack::Alarm.alarm(5) # if no command received in 5 secs

            sock = ::UnixRack::Socket.new(conn)
            @@client_ip = sock.peeraddr.last

            if not sock.read_headers()
              send_error_response!(sock, 400, "Bad Request", "-", "-")
            end

            trap(:ALRM) { log(0, "Child received ALARM during response. Exiting."); exit! 2 }
            ::UnixRack::Alarm.alarm(120) # if command not handled in 120 seconds

            if not allowed_ips.empty?
              if not (allowed_ips.any? { |e| @@client_ip.include? e })
                send_error_response!(sock, 403, "Forbidden", sock.hdr_method[0], sock.hdr_method[1])
              end
            end

            if ["GET", "POST"].include?(sock.hdr_method[0])

              env = {}

              if sock.hdr_method[0] == "GET"
                content = StringIO.new("")
                content.set_encoding(Encoding::ASCII_8BIT) if content.respond_to?(:set_encoding)
              elsif sock.hdr_method[0] == "POST"
                if not sock.headers.include?('Content-Length')
                  send_error_response!(sock, 400, "Bad Request no content-length", sock.hdr_method[0], sock.hdr_method[1])
                end
                if not sock.headers.include?('Content-Type')
                  send_error_response!(sock, 400, "Bad Request no content-type", sock.hdr_method[0], sock.hdr_method[1])
                end

                env["CONTENT_LENGTH"] = sock.headers['Content-Length']
                env["CONTENT_TYPE"] = sock.headers['Content-Type']

                # F the 1.1
                if sock.headers.include?('Expect')
                  if sock.headers['Expect'] == '100-continue'
                    ::UnixRack::Socket.write_buff(sock.sock, "HTTP/1.1 100 Continue\r\n\r\n")
                  else
                    send_error_response!(sock, 417, "Expectation Failed", sock.hdr_method[0], sock.hdr_method[1])
                  end
                end

                # It is required that we read all of the content prior to responding
                content = sock.read_content
                content.set_encoding(Encoding::ASCII_8BIT) if content.respond_to?(:set_encoding)

                if content == nil
                  send_error_response!(sock, 400, "Bad Request not enough content", sock.hdr_method[0], sock.hdr_method[1])
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

              env["SCRIPT_NAME"] = ''
              env["PATH_INFO"] = uri_parts[0]
              env["QUERY_STRING"] = uri_parts[1]

              env["SERVER_NAME"] = host
              env["SERVER_PORT"] = port
              env["REMOTE_ADDR"] = @@client_ip

              if sock.headers['User-Agent']
                env["HTTP_USER_AGENT"] = sock.headers['User-Agent']
              end
              if sock.headers['Cookie']
                env["HTTP_COOKIE"] = sock.headers['Cookie']
              end
              if sock.headers['Authorization']
                env["HTTP_AUTHORIZATION"] = sock.headers['Authorization']
              end
              if sock.headers['Range']
                env["HTTP_RANGE"] = sock.headers['Range']
              end
              if sock.headers['X-Real-IP']
                env["HTTP_X_REAL_IP"] = sock.headers['Real-IP']
              end
              if sock.headers['X-Forwarded-For']
                env["HTTP_X_FORWARDED_FOR"] = sock.headers['X-Forwarded-For']
              end
              if sock.headers['X-Forwarded-Proto']
                env["HTTP_X_FORWARDED_PROTO"] = sock.headers['X-Forwarded-Proto']
              end
              if sock.headers['Host']
                env["HTTP_HOST"] = sock.headers['Host']
              end

              env["HTTP_VERSION"] = "HTTP/1.1"
              if sock.headers['If-Modified-Since']
                env["HTTP_IF_MODIFIED_SINCE"] = sock.headers['If-Modified-Since']
              end

              env.update({"rack.version" => [1, 1],
                          "rack.input" => content,
                          "rack.errors" => $stderr,
                          "rack.multithread" => false,
                          "rack.multiprocess" => true,
                          "rack.run_once" => true,
                          "rack.url_scheme" => "http"
                         })

              # Reminder of how to do this for the future the '::' I always forget
              #::File.open('/tmp/dru', 'a') do
              #  |f2|
              #  f2.syswrite(env.inspect + "\n")
              #end
              status, headers, body = app.call(env)

              send_response!(sock, status, sock.hdr_method[0], sock.hdr_method[1], headers, body)

            end

            send_error_response!(sock, 500, "Server Error", sock.hdr_method[0], sock.hdr_method[1])
          end
        end
      end

    end
  end
end

Rack::Handler.register 'unixrack', 'Rack::Handler::UnixRack'
