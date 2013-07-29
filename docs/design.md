
RQ


RQ is a simple queuing system based on message passing.

Every


Architecture

The system exists in one directory. The commands to operate on a queue are bound to the queues in the directory the commands exist in.

The system is composed of a web server and a supervisor process. The webserver is Sinatra running on Rack running on Webrick. This may change.
All processes are single threaded.
The web server communicates with the supervisor process on a unix domain socket.

There will only be one supervisor process. 
The supervisor process starts up queue supervisor (quesup) processes for all the queues.
Any children of any process will have a pipe to their parent. If that pipe goes away, a child should shut down immediately. 

There should only be one quesup for a given queue. A file-lock will be used for safety.
Since there is only one, no locks are required in the filesystem to manage the queue for injection.


It handles all communication and 


REST API Influences
http://wiki.developer.myspace.com/index.php?title=RESTful_API
Couch DB
http://wiki.apache.org/couchdb/HTTP_Document_API


BIN Dir

We have a binary directory for future CLI compatability.



Special queue: relay

The queue states

prep
que
run
  - starting
  - running
  - finishing
done
  - relay
err


Two-Phase Commit for Protocol

... avoids duplicate sends or 

Sender         Receiver
------         --------
if no id,
         -----> alloc_id
   id    <-----

else
 use stored
 id
         -----> prep, id
 ok |        <-----
  -> continue
 fail/unknown |    <-----
  -> fail job
 ok/already commited |    <-----
  -> mark job done

continue:
  modify or make
  attachments
         <----->  attach/etc

ok, commit
          ----->  commit
 ok |        <-----
  -> mark job done

* Note - it is possible to have duplicate sends.
  If a message gets commited, but we feel it is a fail,
  we may eventually try to resend. If we hit a new machine,
  then we will restart the process and resend. If the old
  machine comes back up, it will retart its message handling.

