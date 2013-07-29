
#goals get a web server install up
#install queu dir
#Create IPC system
#Restart Server Command
#Test non block
#See server Uptime (JSON result)
#Create queues (local and other)
#See Queue List (JSON result)
#Change queue process name
#Fix bug with spaces in queue names and script names
#Detect queue death and restart
#Have QueueSupervisor shut down children upon shutdown
#Git checkin
#Lite Click on queues to dig deeper
  + main page has links
  + queue page has info

Monday
------
#Add to git.btrll.com repo
+Queue status
  + store status
  + return status
  + Lite-web queue process restart (hit a link, does restart, says
  'OK', you hit back button)

+QueueSupervisor state
  + Try to start queues (just start any queue with a dir)

+Lite Queue startup -> verify dirs -> loads state (operational status)
?Move administrative state to queuemgr
 - Maybe queue process is always up, though?, yeah, quemgr just loads
 procs
  
+ Identify message ID and attribs, make an object
+ Lite queue message manipulation
  + inject message
  - delete message
+Have Queue show num messages in store
+Have Queue show list of messages in store
+Lite Have a message data store (ordered)

Tuesday
-------
+ Design doc -> simple supervisor model, simple understanding of locking
+ Children detect parent death and die
+ Multiple queue dirs
    ['_lock', 'w'], -> lockfile for queue
    ['_log',  'w'],
    ['_tmp',  'd'],
    ['prep',  'd'], -> prep
    ['que',   'd'], -> queued
    ['run',   'd'], -> running (for a 1 worker queue, 1 at a time)
    ['pause', 'd'], -> running (for a 1 worker queue, 1 at a time)
    ['done',  'd'], -> done (removed, errored and removed, etc)
    ['_err',  'd'], -> error (malformed, unfinished?)
?A New FileQue class

+Sleep random for inject
+Change 'queue' to 'q' in message id and url
+Change 'messages' status to show all q's
+Have q inject go to actual q
 + change form
 + change controller
+ Reverse presentation of messages in a queue

+ Queue a job via cmd line (using ruby lib)
  + simple message
  + file attachment via same filesystem (check stat.dev for equality)
  + file attachment via diff filesystem (make a temp file, copy file)
  + return full msg_id with q_name back
+ Lite show/delete routing
+ Lite delete message
+ Lite show message

*milestone 1*

Have a local queue script deliver message to a local queue
 + scheduler wakes up on injection
 + Create a simple script that writes its ENV to a log (verify file descriptors,etc)
 + run a script in an environment for message
  + Have a script to run. if script fails. queue is stopped.
  + Child script is monitored by this process
    + notice pipe, exit
   + queue states
     +run - started / process message
     +run - running / (time remaining x secs -or- Ykb of Zkb remaining
                       -or- X bytes of Z bytes processed)
     -done  - Proper status exit with 0 process return (diff fileque)
     -fail  - Any process exit without commit (diff fileque)
     -relay - Another proper status exit - new ID
     -reschedule - Another proper status exit - same ID, new due date
    - properly move job to done when done
   x queue reads run states from disk on restart
  x lite restart queue, re-run scheduler
   + script runs and has an environment
   + script runs and has an environment and a log
     - should that be via IPC? (cheap)
     x or via a program? (expensive)
    x both
 + a format that is bash friendly
 + KINDA - a buffer for pipe reads? (must do properly)
 + test with Bash
 + handle proper completion done/fail/relay/resend
  + done - just move into that dir
  + fail - move into that dir
  + relay - indicate that the job was relayed to a url
  + resend - delay time - requeue, and log some messages

 Tuesday
 + a simple test curl script to create a queue and messages to it
  + runs tests, detects if tests pass
    + sets up two queues (relay and test)
    + See why messages are going into relay
    + test script responds to param1
    + script checks job status
 + sends messages
    + 1 for done
    + 1 for fail/err
    + 1 for done with non-zero exit (err)
    + 1 for resend, detect that it was resent
    + Increment RQ_COUNT for every resend
 + a real relay script in ruby that looks at dest of message, notices that
   routing
   + if it is this host
   + if it isn't this host, fail at this time
   + script to test relay
   + 1 for relay, get relay redirect location and done on final queue
   + Store ID
   + Use ID
 + test router script
 + local queue on same host
 + Queue status message should be updated for fail, pause, done, err


 + Test file upload 
   + Hand run curl script
   + Code to put file as attachment into system
   + Attach returns md5 of attachment
   + Test script to upload a file (aka curl) and verify md5

* milestone 2 *
 - Have a test script test this end to end
   + test script uses rq cmd so we need a way to get the list of attachments
   + the list should have the md5
 - Have relay queue script deliver message to a remote queue
 - Require relay script to do multi-part form upload? (nope, curl)

*milestone 3*
 - Have a master test script to run the series of test scripts
 - Have a versioning system
 - DONE


Implement CDB push system
 - Delivers to local
   - Relayed to cdb_push script
   - cdb_push creates new cdb file
   - cdb_push preps new messages to other machines
   - cdb_push waits for all messages to complete or errors out
   - remote machines script moves file into proper location as proper user

*milestone 3*
 - parallel job running
 - test delete message

Later...
 - Test two phase properly
 - Code to return md5s of attachments
 - Code to return md5s and mime/types of attachments
 - Store due dates for jobs in que
 - web queue status for done is propper
 - Lower priority of all children
 - Put children in process groups
 - Properly detect signals that suspend processes
 - Insure that all children get killed (hmm a vote for C)
   Do Linker tricks later
 - Make a partial for queue status
 - Master qmgr cleans up all processes if queue doesn't do so properly
- Bloom filter for Done
  - might be in X, if not - then definitely not
  - might be just lru / array of Y most recent
- System for handling a down machine
  - Tiny window where client doesn't get updated location
  - Admins push jobs somewhere else, generally one machine
  - Admins have host that responds to that queue and sends redir
    response to client
- Proper way to migrate people from a machine
  - Take machine out of pool of machines
  - Watch traffic die down, all jobs flush (once jobs completed,
  generally safe to take down)
  - Take machine offline

- System for respawn flooding (aka wait * 2)
- catch child death via sigchild
- Lite View queue log
- Lite View mesg log
- Attach returns md5
- Alternative to webrick
- Resource managment (memory needs - disk, cpu, etc.)
CLI show message
CLI show queue
Implement lock files for all queues.
Have TMS keep track of last 3 completed jobs per user (in session)
Have TMS keep track of active jobs
 -Message list has length param for packet length on both sides
Lite queue mod administrative and operational state
 - Set to up or down

Control queue states (clean shutdown, hold, go)
Refactor Quemgr to be like queue

Have a script for another queue (cdb push)

Have a local queue script move job to a remote queue

DONE

Restart Server Command via web
View log via web (last 10 entries)
#  Simple IPC via cmd line or web to running process
#    Core is Unix Domain, Web Proxies
Have the queue send job to destination queue (local machine, local filesystem)
Have remote queue deliver
Have remote queue run
