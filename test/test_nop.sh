#!/bin/bash

function write_status {
  echo $1 $2 >&3
  echo $1 $2
}

write_status 'run'  "NOP QUEUE"
echo "done"
write_status 'done' "done sleeping"
