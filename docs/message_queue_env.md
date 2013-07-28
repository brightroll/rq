
RQ
--------------

Current Dir = <que>/<state>/<short msg id>/job/

Full Msg ID = host + q_name + msg_id

ENV["RQ_SCRIPT"]     = The script as is defined in config file
ENV["RQ_REALSCRIPT"] = The fully realized path (symbolic links followed, etc)
                       Should be equivalent to ARGV[0]

ENV["RQ_HOST"]       = Base URL of host (Ex. "http://localhost:3333/")
ENV["RQ_HOSTNAMES"]  = Base URLs of host (aliases) (Ex. "http://localhost:3333/ http://butter:1234/")
                       Split by space

ENV["RQ_DEST"]       = Msg Dest Queue (Ex. http://localhost:3333/q/test/)

ENV["RQ_DEST_QUEUE"] = Just Queue Name (Ex. 'test')

ENV["RQ_MSG_ID"]     = Short msg id (Ex. "20091109.0558.57.780")

ENV["RQ_FULL_MSG_ID"] = Full msg id of message being processed
                       (Ex. http://vidxcode27.btrll.com:3333/q/test/20091109.0558.57.780)

ENV["RQ_MSG_DIR"]    = Dir for msg (Should be Current Dir unless dir is changed
                       by script)

ENV["RQ_READ"]       = Read pipe FD to Queue management process
ENV["RQ_WRITE"]      = Write pipe FD to Queue management process

ENV["RQ_COUNT"]      = Number of times message has been relayed or processed

ENV["RQ_PARAM1"]     = param1 for message
ENV["RQ_PARAM2"]     = param2 for message
ENV["RQ_PARAM3"]     = param3 for message
ENV["RQ_PARAM4"]     = param4 for message

ENV["RQ_FORCE_REMOTE"] = Force remote flag

ENV["RQ_PORT"]       = port number for RQ web server, default = 3333

ENV["RQ_ENV"]        = 'production', 'development', 'test', 'stage'
ENV["RQ_VER"]        = version of rq

--------------

