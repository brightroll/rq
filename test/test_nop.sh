#!/bin/bash

function write_status {
  echo $1 $2 >&$RQ_WRITE
  echo $1 $2
}

write_status 'run'  "NOP QUEUE"
echo "done"
write_status 'done' "done sleeping"
