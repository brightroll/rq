
RQ -- created by Dru Nelson (BrightRoll Inc.)
=============================================

SETUP
-----

1. clone the git repository
2. kill queue manager if it is running (pname: `[rq-mgr]`)
3. delete the config directory if it exists
4. bundle by typing `$ gem bundle` (bundler ~< 1.x.x) or `bundle install`
5. run the installer with `$ bin/webserver.rb install`
6. use a browser to hit the running server, set the domain of the machine
7. restart the `web_server.rb` process (after killing, just `bin/web_server.rb`)

TODO
----

* In UI, on creation -> specify n params in form
* In backend, turn n params into param1 json hash
  * param1 should just become the only param (no need to have 4 enumerated)
