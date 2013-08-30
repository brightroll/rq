

RQ Queue Config JSON

A typical config:

{"ordering":"none","script":".\/code\/relay_script.rb","num_workers":"1","exec_prefix":"","name":"relay"}


Mandatory Fields

name:
Name of the queue.

script:
The path to the script that will process messages in that queue

num_workers:
The number of processes that can run to handle incoming messages. This
is equivalent to the max number of messages that can be in the run state.

Optional Fields
exec_prefix:
This is what is prefixed to the script before the 'exec' system call is made to run the "script". As a default, it is set to 'bash -lc ' if not set. Note the space on the end.

env_vars
This is a map of key value pairs that will be established in the environment per script run.
