

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
example: dup 0-X-http://checkin08.btrll.com/q/barrier_wait<nl>

response:
STATUS SPACE CONTENT
STATUS = ok | fail
CONTENT = for ok: <new message id> | for fail: <some failure message> 

