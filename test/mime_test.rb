#!/usr/bin/env ruby

require 'fileutils'
require 'socket'


def write_buff(io, buff)
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


def do_read(sock)
  begin
    dat = sock.sysread(16384)
  rescue Errno::EINTR  # Ruby threading can cause an alarm/timer interrupt on a syscall
    retry
  rescue EOFError
    puts "#{$$}: Got an EOF from socket read"
    return nil
  rescue Errno::ECONNRESET,Errno::EPIPE,Errno::EINVAL,Errno::EBADF
    puts "#{$$}: Got an #{$!} from socket read"
  end
  return dat
end


def run(msg_id)
  hdr = File.read('test/fixtures/bad_mime.header')

  new_hdr = hdr.sub('XXXXMSG_IDXXXX', msg_id)
  data = File.read('test/fixtures/bad_mime.data')
  port = (ENV['RQ_PORT'] || 3333).to_i
  t = TCPSocket.new('127.0.0.1', port)

  write_buff(t, new_hdr)
  write_buff(t, data)

  result = do_read(t)

  hdr,data = result.split("\r\n\r\n",2)

  if data.index('["ok",') != 0
    puts "Failed MIME bug test. Got: #{data}"
    exit 1
  else
    puts "PASSED MIME bug test."
    exit 0
  end
end


msg_id = ARGV[0]

run(msg_id)

