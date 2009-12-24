require 'rack'

class MiniRouter
  def call(env)
    path = env["PATH_INFO"].to_s.squeeze("/")
    p "PATH: #{path}"

    ## Notice the chaining here, if a path below has a dependency,
    ## that dependency must be handled prior, otherwhise an infinite
    ## redirect loop will occur

    # Gotta deal with static stuff first
    if path.index('/css') or path.index('/javascripts') or path.index('/favicon.ico')
      load 'code/main.rb'
      return Rack::Static.new(nil, :urls => ["/css", "/javascripts", "/favicon.ico"], :root => 'code/public').call(env)
    end

    # Is this an install?
    if path == '/install'
      load 'code/install.rb'
      return RQ::Install.new.call(env)
    end

    # Not set up?? It is an install
    if not File.exists?('config')
      resp = Rack::Response.new()
      resp.redirect('/install')
      return resp.finish
    end

    # Everything else goes into main
    if true #path == '/'
      load 'code/main.rb'
      #return Rack::Static.new(RQ::Main.new, :urls => ["/css", "/javascripts"], :root => 'code/public').call(env)
      return RQ::Main.new.call(env)
    end
  end
end
