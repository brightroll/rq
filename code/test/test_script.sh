#!/bin/bash

function write_status {
  echo $1 $2 >&3
}


write_status 'run'  "just started"
echo "TESTTESTTEST"
write_status 'run' "a little after just started"
#sleep 1

pwd

if [ "$RQ_PARAM1" == "html" ]; then
  echo "<span id='envspan' style='color: blue;'>"
fi
env | grep RQ_
if [ "$RQ_PARAM1" == "html" ]; then
  echo "</span>"
fi

echo "----------- all env ---------"
env
echo "-----------------------------"

lsof -p $$

write_status 'run' "post lsof"

#write_status 'run' "sleeping 1"
#sleep 1


#write_status 'run' "done sleeping"



if [ "$RQ_PARAM1" == "err" ]; then
  echo "This script should end up with err status"
  write_status 'err' "by design"
  exit 0
fi

if [ "$RQ_PARAM1" == "sneaky" ]; then
  echo "This script should *still* end up with err status"
  write_status 'done' "sneaky non-zero exit"
  exit 1
fi

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

echo "done"
write_status 'done' "done sleeping"


