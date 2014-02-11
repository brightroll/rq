module RQ
  class PortaProc

    attr_accessor :list

    def get_list
      @list = []

      # Cross-Platform ps command
      out = %x[/bin/ps -A -o uid,pid,ppid,sess,command 2>&1] or fail false, out

      lines = out.split("\n")

      # mutator
      hdr = lines.shift

      items = lines.map { |i|
        f = i.split(" ", 5)
        h = { :uid => f[0], :pid => f[1], :ppid => f[2], :sess => f[3], :cmd => f[4] }
      }

      return true,items
    end

  end
end
