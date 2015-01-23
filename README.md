# RQ

RQ is a **simple** queueing/messaging system for *any* Unix system and can
process messages in **any language**. It is designed to run on every machine
in your distributed system. Think of it as another one of those small, but
important services (like crond). It uses directories and json text files on the
Unix filesystem as its database. It does not use a specialized database. As a
result, it is easy to understand and debug.

Each item in the queue is a **Message**. Messages can be small, but RQ was
designed for a medium to large granularity. For example, messages could have
attachments with 100s to 1000s of megabytes. Each message can be processed by
the local machine or relayed reliably to another machine for processing. These
machines don't have to be in the same data center and in fact can be on another
continent. When a message is received in a queue, a worker process is started
to process the message. The worker process is one-to-one with a unix process.
(some call this a 'forking' model). The code required to implement a worker is
very small. Also, API is compatible with any language that runs on Unix. While
a worker is processing a message, you can view a real-time display of logs
(with ANSI colors) via the browser.

Here is a sample screenshot of a single queue:

![Screen Shot](docs/rq_screen_shot.png "Example Screen Shot")

## A brief overview of the system.
Once RQ is installed, the user creates a queue. The queue requires only a few
parameters, but the most important one is the 'queue script'. This is a program
written in *any* language that will process each message. The API for the queue
script is easy to implement and described below. Whenever a message is received
on that queue, this program runs. The program will either succeed, fail, or ask
to retry *x* seconds in the future. If the script takes a long time to run, it
can send periodic updates to RQ to indicate progress. The script can also
provide a lot of logging and produces large files as output.

The RQ system provides a REST, HTML, cmd-line, or low-level socket API to work
with messages and queues. That is all there is to it.

When would you use RQ?
In a typical web application, you should always respond to the browser within a
small time frame. You should also avoid using a lot of memory in this section
of your application stack as well. If you know a particular computation will
exceed those requirements, you should hand off the task to a queueing system.

If you have scripts that run via cron, you should probably run that under RQ.
In this scenario, RQ will monitor that the script properly executed.

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
* Periodically rotate and send HTTP logs to a NoSQL database for search and analysis
* Verify URLs with Internet Explorer (and take screenshots) on a box controllable via a simple web api
* Spin up EC2 instances via AWS API


Table Of Contents
-----------------

* [Quick Setup](#section_Quick_Setup)
* [Features](#section_Features)
* [Hip Tips](#section_Hip_Tips)
* [Config Files](#section_Config_Files)
* [Queue Config Files](#section_Queue_Config_Files)
* [Guarantees](#section_Guarantees)
* [Your First Queue Script](#section_Your_First_Queue_Script)
  * [Ruby](#section_Ruby)
  * [Bash](#section_Bash)
* [Queue Script API](#section_Queue_Script_API)
  * [Environment](#section_Environment)
  * [Logs and Attachments](#section_Logs_and_Attachments)
  * [Pipe Protocol](#section_Pipe_Protocol)
* [Special Queues](#section_Special_Queues)
* [Internals](#section_Internals)
  * [Queue States](#section_Queue_States)
* [Contributors](#section_Contributors)


<a name='section_Quick_Setup'></a>
## Quick Setup

1. Clone this git repository
1. Run `./bin/rq-install` to create a config and a set of default queues.
1. Run `./bin/rq-mgr start` to start the rq-mgr process, one RQ process per queue, and the web interface.
1. Run `./test/run_tests.sh` to exercise the test suite.

An init style startup script is provided in `bin/rc.rq`, you may copy or symlink it to your system init directory.

RQ returns a complete HTTP URL for each enqueued message, therefore you must configure RQ with the canonical hostname for real-world use.

<a name='section_Features'></a>
## Features

<a name='section_Hip_Tips'></a>
## Hip Tips

* Scripts should be idempotent if at all possible.
* Messages should not go to error frequently
  * RQ can retry a message if the error is transient. If this is happening, something is wrong with your assumptions.
* Do not fire and forget an RQ message.
  * It is ok to be more lax in side of the queue script that processes that message
* Log output that might help someone other than you diagnose the issue
* Crypto - sign and encrypt your message before giving it to RQ. Secure channels is too hard of a problem.
* Use the status system for progress updates
* Do not run RQ in production with the name 'localhost'
* Master passing - Do not access other message directories unless the message is `done`
* Don't take too long via the Web UI, there is a X second timeout

<a name='section_Config_Files'></a>
## Config Files

At the top level, `config/config.json` provides primary configuration. A typical
config:

config.json
``` json
{"env":"development","host":"127.0.0.1","port":"3333","addr":"0.0.0.0","tmpdir":"/tmp",
 "relative_root":"/therq",
 "basic_auth":{
  "realm":"Your RQ",
  "users":{
   "foo user":"bar pass"
} } }
```

Key                   | Description
:--                   | :----------
**env**               | Environment for RQ_ENV
**host**              | Hostname used for canonical full message ID
**port**              | Port for the web UI to listen on (required, but default is 3333)
**addr**              | Addr for the web UI to listen on (0.0.0.0 for all interfaces)
**tmpdir**            | Directory for temp files
allow_new_queue       | Boolean, enable the new queue web UI, default `false`
relative_root         | Path prefix for the web UI, default `/`
basic_auth            | Hash for HTTP Basic authentication, has two required elements
basic_auth: **realm** | Realm for HTTP Basic
basic_auth: **users** | Hash of username:password pairs

_Fields in **bold** are mandatory, all others are optional._

<a name='section_Queue_Config_Files'></a>
## Queue Config Files

Within each queue directory, the files `config.json` and `form.json` provide
configuration. A typical config:

config.json
``` json
{"name":"interval_do_work","script":"/usr/bin/interval_script.sh","num_workers":5,
 "schedule":[
  {"cron":"*/10 * * * *",  "param1":"10m"},
  {"cron":"@hourly",       "param1":"1h"}
] }
```
form.json
``` json
{"default":"hidden","mesg_param1":{"label":"Frequency of run","help":"Tell the script its run interval"}}
```

Key                  | Description
:--                  | :----------
**name**             | Name of the queue
**script**           | Path to the script to execute for each message
num_workers          | Maximum number of messages to process at a time, default `1`
exec_prefix          | This is prepended to the script path before calling `exec()`, default `bash -lc`
env_vars             | Hash of environment variables and values set before calling `exec()`, default empty
coalesce             | Boolean, whether to coalesce messages with identical paramters, default `false`
coalesce_paramN      | Boolean, if coalesce is true, whether to coalesce on a particular parameter
schedule             | Array of hashes of cron-like scheduled jobs
schedule[]: **cron** | A cron-like five element recurring schedule, see crontab(5)
schedule[]: paramN   | Optional param1-param4 will be passed to each scheduled job

_Fields in **bold** are mandatory, all others are optional._

Scheduled jobs may be queued up to 1 minute in advance, with a `due` time set to
match the scheduled time. Scheduled jobs will only be created if the queue is in
`UP` state - a paused or downed queue will not schedule new jobs. Multiple
schedules are supported and each can have different params.

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

<a name='section_Ruby'></a>
### Ruby

Here's a simple example script in Ruby:

``` ruby
#!/usr/bin/env ruby

# NOTE: Ruby buffers stdout, so you must fflush if you want to see output
#       in the RQ UI

end

def write_status(state, mesg = '')
  io = IO.for_fd(ENV['RQ_WRITE'].to_i)
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

Here's a simple example script in Bash:

``` bash
#!/bin/bash

# The variable RQ_WRITE is a pipe to the RQ queue
function write_status {
  echo $1 $2 >&$RQ_WRITE
}

# The variable RQ_READ is a pipe from the RQ queue
function read_status {
  read -u $RQ_READ
}

write_status "run"  "Looking for RQ environment variables"

echo "----------- RQ env ---------"
env | grep RQ_
echo "-----------------------------"

write_status "run" "Finished looking for RQ environment variables"

if [ "$RQ_PARAM1" == "slow" ]; then
  echo "This script should execute slowly"
  write_status "run" "start sleeping for 30"
  sleep 30
  write_status "run" "done sleeping for 30"
fi

if [ "$RQ_PARAM1" == "err" ]; then
  echo "This script should end up with err status"
  write_status "err" "by design"
  exit 0
fi

if [ "$RQ_PARAM1" == "duplicate" ]; then
  echo "This script should create a duplicate to the test_nop queue"
  write_status "run" "start dup"
  write_status "dup" "0-X-test_nop"
  read_status

  if [ "$REPLY" != "ok" ]; then
    echo "Sorry, system didn't dup test message properly : $REPLY"
    write_status "err" "duplication failed"
    exit 0
  fi

  if [ "$REPLY" == "ok" ]; then
    write_status "run" "done dup"
  fi
fi

write_status "done" "script completed happily"
```

<a name='section_Queue_Script_API'></a>
## Queue Script API

<a name='section_Environment'></a>
### Environment

When a queue has a message to process, and a slot is available to run, the
queue script will be executed in a particular environment. This environment
passes information about the message to the script via two ancient forms of
Interprocess Communication: Environment variables and the filesystem.

Current Dir = [que]/[state]/[short msg id]/job/

Full Msg ID = host + q_name + msg_id

Variable        | Description
:-------        | :----------
RQ_SCRIPT       | The script as is defined in config file
RQ_REALSCRIPT   | The fully realized path (symbolic links followed, etc)
RQ_HOST         | Base URL of host (Ex. "http://localhost:3333/")
RQ_DEST         | Msg Dest Queue (Ex. http://localhost:3333/q/test/)
RQ_DEST_QUEUE   | Just Queue Name (Ex. 'test')
RQ_MSG_ID       | Short msg id (Ex. "20091109.0558.57.780")
RQ_FULL_MSG_ID  | Full msg id of message being processed (Ex. http://rq.example.com:3333/q/test/20091109.0558.57.780)
RQ_MSG_DIR      | Dir for msg (Should be Current Dir unless dir is changed by script)
RQ_READ         | Read side pipe FD to the Queue management process
RQ_WRITE        | Write side pipe FD to the Queue management process
RQ_COUNT        | Number of times message has been relayed or processed
RQ_PARAM1       | param1 for message
RQ_PARAM2       | param2 for message
RQ_PARAM3       | param3 for message
RQ_PARAM4       | param4 for message
RQ_FORCE_REMOTE | Force remote flag
RQ_PORT         | port number for RQ web server, default = 3333
RQ_ENV          | Typically one of 'production', 'development', or 'test'
RQ_VER          | RQ version

<a name='section_Logs_and_Attachments'></a>
### Logs and Attachments

<a name='section_Pipe_Protocol'></a>
### Pipe Protocol

A queue script communicates with its parent RQ process over a pair of pipes.
The pipe file descriptor numbers are provided in the RQ_READ and RQ_WRITE
environment variables, named from the perspective of the queue script.

The queue script's stdin is closed, and its stdout and stderr are redirected to a file.

The queue script protocol follows this grammar:

```
CMD Space Text Newline
CMD = run | done | err | relayed | RESEND | DUP

resend detail:
  RESEND     = resend DUE Dash Text
  DUE        = Integer

dup detail:
  DUP        = due Dash FUTUREFLAG Dash NEWDEST
  DUE        = Integer
  FUTUREFLAG = X
  NEWDEST    = An RQ queue path

dup response:
  STATUS Space CONTENT
  STATUS     = ok | fail
  CONTENT    = for ok: <new message id> | for fail: <failure reason text>
```

For obvious reasons, the Text cannot have any newline characters. There is no
limit to Text length, but in practice it should not exceed a few hundred bytes.

Command | Description
:------ | :----------
run     | When the script is running, it is in 'run'. To send an updated status to the operator about the operation of the script, just send a 'run' with TEXT as the status.
        | example: `run Processed 5 of 15 log files.<nl>`
done    | When the script is finished, and has successfully performed its processing. It sends this response. It *must* also exit with a 0 status or it will go to 'err'.
        | example: `done Script is done.<nl>`
err     | When the script has failed, and we want to message to go to 'err' (probably to notify someone that something has gone wrong and needs operator attention). Any exit status at this point will take the message to 'err'.
        | example: `err Database dump script failed.<nl>`
relayed | This is used by the relay queue and should not be used by a user queue script.
resend  | When the script has failed, but we want to just retry running it again, we respond with a 'resend'. This will cause a message to go back into 'que' with a due time of X seconds into the future.
        | example: `resend 300-Memcached at foo.example.com not responding.<nl>`
dup     | Create a clone of the existing message (including attachments) to the new destination. NOTE: This is the first status response that is a 2 way conversation with the queue process. If the queue does match /^https?:/, then it goes to 'relay' to be sent on. Otherwise it is considered a local. If relay or the local queue doesn't exist or is admin DOWN/PAUSE, then the the response will indicate failure. This resets the current count for the newly generated message.
        | example: `dup 0-X-http://rq.example.com/q/queuename<nl>`

<a name='section_Special_Queues'></a>
## Special Queues

* `cleaner` - this queue's script periodically removes old messages.
* `relay` - this queue's script sends messages to a separate system. Whenever RQ
  locally is given a message that is destined for a separate host, the message
  actually goes into this queue.
* `webhook` - this queue's script does webhook notifications for any message
  that requests it.

<a name='section_Internals'></a>
## Internals

We use Unix Domain Sockets for the primary RPC mechanism. They work just like
TCP sockets, except we don't have to worry about network security. You
rendezvous with the listening process via a special file on the filessystem.
They are better than pipes since they provide 2 way communication.

There are 3 primary systems that make up RQ. The rq-mgr process, the individual
rq queue processes, and the web server process.

The primary process is the rq-mgr process. It sets up a Unix Domain socket and
communicates via that for its primary API. Its primary function is to watch
over and restart the individual RQ *queue* processes. It maintains a standard
Unix pipe to the child RQ process to detect child death.

Each queue gets its own process. They also communicate. These monitor their
queue directories and worker processes. They have the state of the 'que' queue
in memory. It also uses a standard unix pipe to communicate with the rq-mgr.
For queue scripts it maintains.

The web server exists to give RQ a human (HTML) and non-human (REST) interface
using the HTTP standard. This makes it easy to use via a browser, cURL, or with
just about any HTTP lib that comes with any language.

<a name='section_Queue_States'></a>
### Queue States

```
prep
que
run
  - starting
  - running
  - finishing
done
  - relay
err
```

Two-Phase Commit for Protocol

```
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
```

<a name='section_Contributors'></a>
## Contributors

Dru Nelson
http://github.com/drudru
@drudru

Aaron Stone
http://github.com/sodabrew
@sodabrew

The overall concepts are very similar to the original UUCP systems that used to span the internet.

The idea for the directory storage was copied from the Qmail architecture by Dan J. Bernstein.

The code for RQ was largely written in-house.

Thanks to the BrightRoll engineers who used the system to help work the bugs out.

http://github.com/TJeezy is largely responsible for making RQ look a lot better.

I looked to resque for inspiration for this documentation.
I treat it as a goal that I still want to achieve.

Good links on Unix Process stuff:

Daemons in unix
http://www.enderunix.org/docs/eng/daemon.php

Good Link on Straight Up, Old Skool Pipes
http://www.cim.mcgill.ca/~franco/OpSys-304-427/lecture-notes/node28.html

Process control
http://www.steve.org.uk/Reference/Unix/faq_2.html

http://en.wikipedia.org/wiki/Process_group
