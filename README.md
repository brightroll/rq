
# RQ

RQ is a **simple** queueing/messaging system for *any* Unix system and can process
messages in **any language**.
It is designed to run on every machine in your distributed system.
Think of it as another one of those small, but
important services (like crond). It uses directories and json text files on the Unix filesystem
as its database. It does not use a specialized database. This means it is easy to debug and 
understand its internals.
Messages can be small, but RQ was designed for a medium to large granularity.
For example, messages could have attachments with 100s to 1000s of megabytes.
Messages can be processed by the local machine or relayed reliably to another
machine on another continent. The worker system uses a unix process model (some call
this a 'forking' model). It bears some resemblance at a high-level to UUCP.
It has been used in production since 2009 and processed billions of messages at brightroll.
It has a full test suite that verifies the system.
Provides real-time display of logs (even ANSI colors) via the browser.

There is a more distributed option being worked on for the future .
 (Note there is a goal of a more distributed option with MongoDB in the future).

Here is a sample screenshot of a single queue: 

![Screen Shot](docs/rq_screen_shot.png "Example Screen Shot")

## A brief overview of the system.
Once RQ is installed, the user creates a queue. The queue requires only a few
parameters, but the most important one is the 'queue script'. This is a program
written in *any* language that will process the messages. The API for the queue
script is easy to 
implement and described below. Whenever a message is received on that queue,
this program runs. The program will either succeed, fail, or ask to retry X seconds in
the future. If the script takes a long time to run, it can send periodic updates
to RQ to let it know its progress. The script can also provide a lot of logging
and huge files as output.

The RQ system provides a REST, HTML, cmd-line, or low-level sockets
API to work with messages and queues. That is all there is to it.

When would you use RQ?
In a typical web application, you should always respond to the browser within a small
time frame (say 1-3 seconds). You should also avoid using a lot of memory in this section
of your application stack as well. If you know a particular computation will exceed
those requirements, you should hand off the task to a queueing system.

If you have scripts that run via cron, you should probably run that under RQ.  

Here are some examples:

* Transcoding a video file (high cpu)
* Implement a large query for a user in the background
* Have a queue for curl requests for URLs passed in
* A processing pipeline of files stored in S3 (light map/reduce)
  * retrieve
  * filter
  * reduce
  * sftp to partner
* Deploy an update to systems all over the world for user-facing web app (high latency)
* Periodically rotate send HTTP logs (via Ruby Rack) to a MongoDB box for search
* Verify URLs with Internet Explorer (and take screenshots) on a box controllable via a simple web api
* Spin up EC2 instances via AWS api


## Small Dose of Philosophy
The people behind RQ have been working on Unix since the late 1980's. The focus
of RQ has been on reliability and the ease of understanding. The author prefers
systems that allow him to sleep soundly at night, and he thinks the design of 
RQ allows him to achieve this. There is a lot to talk about here and why the existing
systems didn't appeal to the problem. If you are interested in that, read the full
philosphy section below.


Table Of Contents
-----------------

* [Quick Setup](#section_Quick_Setup)
* [Features](#section_Features)
* [Hip Tips](#section_Hip_Tips)
* [Queue Config Vars](#section_Queue_Config_Vars)
* [Guarantees](#section_Guarantees)
* [Your First Queue Script](#section_Your_First_Queue_Script)
  * [Ruby](#section_Ruby)
  * [Bash](#section_Bash)
* [Debugging In Production](#section_Debugging_In_Production)
* [Queue Script Api](#section_Queue_Script_Api)
  * [Environment](#section_Environment)
  * [Logs and Attachments](#section_Logs_and_Attachments)
  * [Pipe Protocol](#section_Pipe_Protocol)
* [RQ Server API](#section_RQ_Server_API)
  * [REST](#section_REST)
  * [cli](#section_cli)
  * [Unix Domain Sockets](#section_Unix_Domain_Sockets)
* [Special Queues](#section_Special_Queues)
* [Patterns](#section_Patterns)
  * [Ruby on Rails](#section_Ruby_on_Rails)
  * [Master Script](#section_Master_Script)
  * [Deploying Code](#section_Deploying_Code)
  * [Webhooks](#section_Webhooks)
* [For The Ops People](#section_For_The_Ops_People)
  * [Monitoring](#section_Monitoring)
  * [Queue States](#section_Queue_States)
  * [Deploying Code](#section_Deploying_Code)
* [For The QA People](#section_For_The_QA_People)
* [Internals](#section_Internals)
  * [Persistence](#section_Persistence)
  * [Relay](#section_Relay)
* [FAQ](#section_FAQ)
* [Philosophy](#section_Philosophy)
* [History](#section_History)
* [Future](#section_Future)
* [Meta](#section_Meta)
* [Contributors](#section_Contributors)


<a name='section_Quick_Setup'></a>
## Quick Setup

You will need:

1. Source to RQ
2. A unique FQDN for the system if production.

Clone the github repo.
Untar the system in a directory of your choosing.

Run `./bin/web_server.rb --install`

Now go to the web UI to follow the steps to complete an installation.

This should setup the RQ directory system and a few default queues.

Run the `/etc/init.d/rq stop` script

There should be no processes with rq running.

Run the `/etc/init.d/rq start` script

This should start several processes. There should be 1 rq-mgr process and one rq process per queue.
There should also be one `web_server.rb` process running.

(Also, I did 

1. clone the git repository
2. kill queue manager if it is running (pname: `[rq-mgr]`)
3. delete the config directory if it exists
4. bundle by typing `$ gem bundle` (bundler ~< 1.x.x) or `bundle install`
5. run the installer with `$ bin/webserver.rb install`
6. use a browser to hit the running server, set the domain of the machine
7. restart the `web_server.rb` process (after killing, just `bin/web_server.rb`)


<a name='section_Features'></a>
## Features

<a name='section_Hip_Tips'></a>
## Hip Tips

* Scripts should be idempotent if at all possible. You should assume that 
* Messages should not go to error frequently
  * RQ can retry a message if the error is transient. let you kno. If this is happening, something is wrong with your assumptions.
* Do not fire and forget an RQ message. 
  * It is ok to be more lax in side of the queue script that processes that message
* Log output that might help someone other than you diagnose the issue
* Crypto - sign and encrypt your message before giving it to RQ. Secure channels is too hard of a problem.
* Use the status system for progress updates
* Do not run RQ in production with the name 'localhost'
* Master passing.Do not access other message directories unless the message is `done`
* Don't take too long via the Web UI, there is a X second timeout

<a name='section_Queue_Config_Vars'></a>
## Queue Config Vars

RQ Queue Config JSON

A typical config:

``` json
{"fsync":"no-fsync","ordering":"none","script":".\/code\/relay_script.rb","num_workers":"1","exec_prefix":"","name":"relay"}
```


** Mandatory Fields **

name:
Name of the queue.

script:
The path to the script that will process messages in that queue

num_workers:
The number of processes that can run to handle incoming messages. This
is equivalent to the max number of messages that can be in the run state.
Default: 1

Optional Fields
exec_prefix:
This is what is prefixed to the script before the 'exec' system call is made to run the "script". As a default, it is set to 'bash -lc ' if not set. Note the space on the end.

env_vars
This is a map of key value pairs that will be established in the environment per script run.

<a name='section_Guarantees'></a>
## Guarantees

* Messages cannot be guaranteed to be delivered in order
* Messages are unique per machine and should use the unique host name
* Messages can be guaranteed to be delivered intact when relayed (MD5)
* RQ will not respond with an OK if a message cannot be commited to disk
* Queue Scripts that are referenced via symlinks are resolved to their full path before execution
  * (This is especially helpful when you have scripts running and you deploy a new version)
* Files are consistent

It *tries* hard to

- insure message is in identical state every run

- avoid duplicate messages
  aka - there is a small chance that messages might be duplicated.

It *does not try* hard to guarantee ordering
  - messages might come in out-of-order. this may happen as a result
    of a failure in the system or operations repointing traffic
    to another rq

given the above, use timestamp versioning to insure an older message
doesn't over-write a newer message. if you see the same timestamp again
for a previously successful txn, it might be that ultra-ultra rare duplicate,
so drop it. 

- You must exit properly with the proper handshake. 


<a name='section_Your_First_Queue_Script'></a>
## Your First Queue Script

When developing an RQ script, you should have a problem in mind that requires just a few parameters.

Next you develop a script. You can skip down just a bit to see some examples.

Typically, you will setup RQ on your development enviornment. Then you will setup a `queue` for your particular
script. Then via the web UI, you will create a new message and submit it. In another tab, you can hit refresh
to the state of the message. If it succeeds, you are done. If not, just edit the code, hit refresh on the tab
that created the message (to resubmit the form and create a new test message), and check on the queue to see if it worked.

Essentially, this turns into a


<a name='section_Ruby'></a>
### Ruby

``` ruby
#!/usr/bin/env ruby

# NOTE: Ruby buffers stdout, so you must fflush if you want to see output
#       in the RQ UI

end

def write_status(state, mesg = '')
  io = IO.for_fd(ENV['RQ_PIPE'].to_i)
  msg = "#{state} #{mesg}\n"
  io.syswrite(msg)
end

write_status('run', "just started")
sleep 2.0

log(cwd)

log(ENV.inspect)

write_status('run', "pre lsof")
log(`lsof -p $$`)
write_status('run', "post lsof")

5.times do
  |count|
  log("sleeping")
  write_status('run', "#{count} done - #{5 - count} to go")
  sleep 1.0
end
log("done sleeping")


log("done")
write_status('done')
exit(0)
```

<a name='section_Bash'></a>
### Bash

Here is a BASH script sample. Yes, even a bash script can handle RQ messages (which was surprising to me!)
The main drawback with BASH as an RQ script is how it deals with functions. I would only use it for
fairly simple scripts.


``` bash

#!/bin/bash

# File Descriptor #3 is pipe back up to RQ parent watcher process
function write_status {
  echo $1 $2 >&3
}


write_status 'run'  "just started"

echo "TEST TEST TEST"

pwd

if [ "$RQ_PARAM1" == "html" ]; then
  echo "html unsafe chars test"
  echo "<HTML "UNSAFE" 'CHARS' TEST & OTHER FRIENDS>"
  echo ""
fi

env | grep RQ_

echo "----------- all env ---------"
env
echo "-----------------------------"

lsof -p $$

write_status 'run' "post lsof"

if [ "$RQ_PARAM1" == "slow" ]; then
  echo "This script should execute slowly"
  write_status 'run' "start sleeping for 30"
  sleep 30
  write_status 'run' "done sleeping for 30"
fi

if [ "$RQ_PARAM1" == "slow1" ]; then
  echo "This script should execute slowly"
  write_status 'run' "start sleeping for 1"
  sleep 1
  write_status 'run' "done sleeping for 1"
fi

if [ "$RQ_PARAM1" == "slow3" ]; then
  echo "This script should execute slowly"
  write_status 'run' "start sleeping for 3"
  sleep 3
  write_status 'run' "done sleeping for 3"
fi

if [ "$RQ_PARAM2" == "err" ]; then
  echo "This script should end up with err status"
  write_status 'err' "by design"
  exit 0
fi

if [ "$RQ_PARAM1" == "dup_direct" ]; then
  # Todo: need something better than a free roaming rm
  rm -f "$RQ_PARAM2"
  echo "This script should create a duplicate to the test_nop queue"
  write_status 'run' "start dup"
  write_status 'dup' "0-X-test_nop"
  read_status
  echo "Got: [${RETURN_VAR[@]}]"

  if [ "${RETURN_VAR[0]}" != "ok" ]; then
    echo "Sorry, system didn't dup test message properly : ${RETURN_VAR}"
    echo "But we exit with an 'ok' the result file won't get generated"
  fi

  if [ "${RETURN_VAR[0]}" == "ok" ]; then
    # Old school IPC
    echo "${RETURN_VAR[1]}" > "$RQ_PARAM2"
  fi
  write_status 'run' "done dup"
fi

if [ "$RQ_PARAM1" == "dup_fail" ]; then
  # Todo: need something better than a free roaming rm
  rm -f "$RQ_PARAM2"
  echo "This script should create a duplicate to a non-existent queue"
  write_status 'run' "start dup"
  write_status 'dup' "0-X-nope_this_q_does_not_exist"
  read_status
  echo "Got: [${RETURN_VAR[@]}]"
  # Old school IPC
  echo "${RETURN_VAR[@]}" > "$RQ_PARAM2"
  write_status 'run' "done dup"
fi

if [ "$RQ_PARAM1" == "resend1" ]; then
    if [ "$RQ_COUNT" == "0" ]; then
        echo "This script should resend the current job at a new time"
        write_status 'resend' "2"
        exit 0
    fi
fi

if [ "$RQ_PARAM1" == "resend2" ]; then
    if [ "$RQ_COUNT" -lt 6 ]; then
        echo "This script should resend the current job at a new time"
        echo "count: ${RQ_COUNT}"
        write_status 'resend' "0"
        exit 0
    fi
fi

if [ "$RQ_PARAM2" == "resend1" ]; then
    if [ "$RQ_COUNT" == "0" ]; then
        echo "This script should resend the current job at a new time"
        write_status 'resend' "8"
        exit 0
    fi
fi

if [ "$RQ_PARAM1" == "symlink" ]; then
  echo "This script should end up with a done status"
  echo $0
  write_status 'done' "${0}"
  exit 0
fi

echo "done"
write_status 'done' "done sleeping"
```

<a name='section_Debugging_In_Production'></a>
### Debugging In Production

Errors do happen in production in ways we cannot anticipate.

For example, you may
Here is a BASH script sample. Yes, even a bash script can handle RQ messages (which was surprising to me!)
The main drawback with BASH as an RQ script is how it deals with functions. I would only use it for
fairly simple scripts.

<a name='section_Queue_Script_Api'></a>
## Queue Script Api

<a name='section_Environment'></a>
### Environment

When a queue has a message to process, and a slot is available to run, the queue script
will be executed in a particular environment. This environment passes information about the message
to the script via two ancient forms of Interprocess Communication: Environment variables and the filesystem.

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
                       (Ex. http://vidxcode27.vbtrll.com:3333/q/test/20091109.0558.57.780)

ENV["RQ_MSG_DIR"]    = Dir for msg (Should be Current Dir unless dir is changed
                       by script)

ENV["RQ_PIPE"]       = Pipe FD to Queue management process

ENV["RQ_COUNT"]      = Number of times message has been relayed or processed

ENV["RQ_PARAM1"]     = param1 for message
ENV["RQ_PARAM2"]     = param2 for message
ENV["RQ_PARAM3"]     = param3 for message
ENV["RQ_PARAM4"]     = param4 for message

ENV["RQ_FORCE_REMOTE"] = Force remote flag

ENV["RQ_PORT"]       = port number for RQ web server, default = 3333

ENV["RQ_ENV"]        = 'production', 'development', 'test', 'stage'
ENV["RQ_VER"]        = version of rq

<a name='section_Logs_and_Attachments'></a>
### Logs and Attachments

<a name='section_Pipe_Protocol'></a>
### Pipe Protocol

<a name='section_RQ_Server_API'></a>
## RQ Server API

<a name='section_REST'></a>
### REST

RQ traditionally runs on port 3333.


<a name='section_cli'></a>
### cli

<a name='section_Unix_Domain_Sockets'></a>
### Unix Domain Sockets

<a name='section_Special_Queues'></a>
## SpecialQueues

`cleaner` - this queue removes old messages
`relay` - this queue sends messages to a separate system
Whenever RQ is given a message that is destined for a separate host, the message actually
goes into this queue.

`rq_router` - this queue handles the 'RQ Router' mode described in the
[For The Ops People](#section_For_The_Ops_People) below.

`webhook` - this queue does webhook notifications for any message that requests it

<a name='section_Patterns'></a>
## Patterns

<a name='section_Ruby_on_Rails'></a>
### Ruby on Rails

Typically, what we have done to run Rails code is to just have the `queue script` 
setup the environment and run the `./script/runner` facility that rails provides..  

<a name='section_Master_Script'></a>
### Master Script

<a name='section_Webhooks'></a>
### Webhooks

<a name='section_Deploying_Code'></a>
### Deploying Code

<a name='section_For_The_Ops_People'></a>
## For The Ops People

RQ can do a few things that aren't obvious above. 

One important topic to cover is the 'RQ Router' mode. In this mode, you basically have
a system or pair of systems set up to process.

<a name='section_Monitoring'></a>
### Monitoring

<a name='section_Queue_States'></a>
### Queue States

<a name='section_Deploying_Code'></a>
### Deploying Code

<a name='section_For_The_QA_People'></a>
## For The QA People

A question that comes up occassionaly is, how do I test an RQ script?

Right now, the best answer is to create a test environment with the RQ server and queue set up.

Then inject messages into the queue and verify that the messages are consumed and processed correctly.

<a name='section_Internals'></a>
## Internals

Currently RQ is written in Ruby.
Ruby definitely has its problems, but overall was an excellent choice.
For more on that decision, see the [History](#secion_History) below.

RQ depends heavily on the Unix API.

We use Unix Domain Sockets for the primary RPC mechanism. They work just like TCP sockets, except
we don't have to worry about network security. You rendezvous with the listening process via a 
special file on the filessystem. They are better than pipes since they provide 2 way communication.

There are 3 primary systems that make up RQ. The rq-mgr process, the individual rq queue processes, and the 
web server process.

The primary process is the rq-mgr process. It sets up a Unix Domain socket and communicates via that for 
its primary API. Its
primary function is to watch over and restart the individual rq *queue* processes. It maintains a standard
Unix pipe to the child rq process to detect child death.

Each queue gets its own process. They also communicate . These monitor their queue directories and worker processes. They have
the state of the 'que' queue in memory. It also uses a standard unix pipe to communicate with the rq-mgr.
For queue scripts it maintains.

The web server exists to give RQ a human (HTML) and non-human (REST) interface using the HTTP standard. This makes
it easy to use via a browser, cURL, or with just about any HTTP lib that comes with any language.

<a name='section_Persistence'></a>
### Persistence

The system

<a name='section_Relay'></a>
### Relay

<a name='section_FAQ'></a>
## FAQ

<a name='section_Philosophy'></a>
## Philosophy

When working in distributed systems, you will eventually learn that some part of the system will be down or unavailable
for many unknown reasons. For example, 

* DNS update breaks dns in infrastructure
* Change or failure in network switch makes 

Also, when working in a large system, you end up having many parts that are important, but not the critical path.
There are also many layers, and developers cannot anticipate all of the different errors that can occur.
Given the lack of priority, sometimes you just need a system that is easy to diagnose and fix. 

Unfortunately, most systems are designed so that the framework to deal with the above is left to the engineers.
For example, everybody agrees that errors are bad and will occur. Yet there are many systems that will silently
 ignore errors.

There is also a general lack of understanding of Unix best practices. For example, when DHH proclaimed to 
'cheat' by running ImageMagick in a separate process, this was a huge revelation to the community.
Overall, people 

RQ is designed to mitigate a large portion of this.

It is process based. This eliminates the single message taking down the whole system problem

<a name='section_History'></a>
## History

During my career, it was common to see people rediscover the need for queueing systems over and over again.
Typically, there is a spectrum for queueing systems. On one end there is the high-speed, message bus
type system that runs a stock exchange. On the other end of the spectrum, you could consider email.

Typically, properly implemented queueing systems required serious infrastructure.
In fact, because of performance issues, most of these do not persist to disk.
The high-end ones have complex APIs and usually are designed for small message sizes.

Then there are the home grown systems which are usually implemented on Redis or memcache

Then there are the basic ones that run off of a SQL database.

All of these require external systems to handle the state.

I decided to make several bets:

1. There might be a quadrant for a general purpose, lightweight queue manager that existed per machine
2. The system should be able to move huge files
3. Ruby was a *good enough* systems language
4. The Ruby VM would be much better within a few years
5. The Unix filesystem would be fast enough

However, only a few of these panned out.

At the time, it was the goto language of choice at BrightRoll.
Other languages were considered that were significantly different than Ruby, but didn't seem 
appropriate.

* Java - memory footprint is way too high. POSIX support is poor (process control, signals, etc.).
* Python - practically equivalent to Ruby, and most were rubyists
* NodeJS - was not nearly baked, very promissing. They are the only system to get Unix since C.
* Go / Golang - may not have existed. If it did, it surely was not baked.
* Erlang - interesting language under consideration. I really liked the concurrency model, but the 
           environment was way too out of our experience zone.
* Lisp, ML, Haskell,  etc. - A lot like Erlang, except without a good concurrency model.
* C - would take way too much time
* C++ - even more time than C

My goals were:

* Get something running
* Should be easy to install (think PHP apps... through the browser)
* Should be easy to update (think Wordpress)
* No dependencies with Ruby (it should just work)

Of all of those, only the first occurred.

Again, Ruby was a good choice.
It was pretty easy to get certain features implemented and into production. The three biggest
drawbacks to ruby were

1. Poor IO support for async IO
2. GEMS. GEM conflicts are a huge problem. 
3. Overall speed of the language

- When it was initially developed on Mac OS X, it was immediately discovered that the directories would have
  to be named (.noindex) as the activity of RQ caused a tremendous load on Spotlight.
  Now I do my development of RQ via ssh to a VirtualBOX Ubuntu instance.
- We ran into the GLIBC issue where DNS would no longer round-robin.

Yet, even with these drawbacks, the overall architecture proved to work pretty well. The forking model hides
most of the issues that someone would run into with.

<a name='section_Future'></a>
## Future

* Address weaknesses
  * Performance - Light message throughput is poor due to Unix filesystem performance
  * Distributed Worker Model - balanced systems
  * Stronger API for Queue Scripts based on JSON
  * Better integration with graphite

* Rewrite the components of the system in C
  * This will keep the memory requirements lower than any other system
  * This avoids all of the negatives that Ruby brings when doing systems work
  * Much better system level control and accounting is possible
* Distributed Worker Model with MongoDB
  * Without changing the Queue Script API, have workers check in
    with a cluster of RQ managers
  * These managers use MongoDB for persistent queue state 
  * MongoDB provides a highly reliable, single-data center store
* Have another persistent store

<a name='section_Meta'></a>
## Meta

This document was produced via Emacs in Viper Mode.

This project uses [Semantic Versioning][sv].

<a name='section_Contributors'></a>
## Contributors

Dru Nelson
http://github.com/drudru 
@drudru

The overall concepts are very similar to the original UUCP systems that use to span the internet.

The idea for the directory storage was copied from the Qmail architecture by Dan J. Bernstein.

The code for RQ was largely written in-house.  

Thanks to the BrightRoll engineers who used the system to help work the bugs out.

http://github.com/TJeezy is largely responsible for making RQ look a lot better.

I looked to resque for inspiration for this documentation. I treat it as a goal that I still
want to achieve.

[sv]: http://semver.org/

Ye Old Stuff
--------------------------------------------------

SETUP
-----

TODO
----

* In UI, on creation -> specify n params in form
* In backend, turn n params into param1 json hash
  * param1 should just become the only param (no need to have 4 enumerated)





Queue Script Processing

Each queue script runs as a child of an rq process for that queue.
The queue script process communicates with that process via a simple pipe.
The stdio fds (stdout and stderr) are redirected to a file.

By sending the following:

CMD SPACE TEXT NL

Where: 

CMD = run | done | err | relayed | resend | dup

For obvious reasons, the TEXT cannot have any newline characters.
The 'TEXT' should be small in size.  There is no limit, but realistically, anything over 200 characters is probably unneccessary. 

CMD Codes

run - When the script is running, it is in 'run'. To send an updated status to the operator about the operation of the script, just send a 'run' with TEXT as the status.
example: run Processed 5 of 15 log files.<nl>

done - When the script is finished, and has successfully performed its processing. It sends this response. It *must* also exit with a 0 status or it will go to 'err'.
example: done done<nl>

err - When the script has failed, and we want to message to go to 'err' (probably to notify someone that something has gone wrong and needs operator attention). Any exit status at this point will take the message to 'err'.
example: err Mysql dump script failed.<nl>

resend - When the script has failed, but we want to just retry running it again, we respond with a 'resend'. This will cause a message to go back into 'que' with a due time of X seconds into the future.
resend TEXT = DUE DASH REASON
DUE = num seconds to wait from now
REASON = free text
example: resend 300-Memcached reflow-west.btrlll.com not responding.<nl>

relayed - This is used by the relay queue and should not be used by a user queue script.

dup - Create a clone of the existing message (including attachments) to the new destination.
NOTE: This is the first status response that is a 2 way conversation with the queue process.
If the queue does match /^https?:/, then it goes to 'relay' to be sent on. Otherwise it is considered
a local. If relay or the local queue doesn't exist or is admin DOWN/PAUSE, then the the response
will indicate failure. This resets the current count for the newly generated message.

dup TEXT = DUE DASH FUTUREFLAG DASH NEWDEST
DUE = num seconds to wait from now (USE 0 for NOW) to run
FUTUREFLAG = 'X' for now now
NEWDEST = proper RQ destination queue 
example: dup 0-X-http://blocking08.vbtrll.com/q/barrier_wait<nl>

response:
STATUS SPACE CONTENT
STATUS = ok | fail
CONTENT = for ok: <new message id> | for fail: <some failure message> 



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

Good links on Unix Process stuff:


Daemons in unix
http://www.enderunix.org/docs/eng/daemon.php

Good Link on Straight Up, Old Skool Pipes
http://www.cim.mcgill.ca/~franco/OpSys-304-427/lecture-notes/node28.html

Process control
http://www.steve.org.uk/Reference/Unix/faq_2.html

http://en.wikipedia.org/wiki/Process_group
