#!/bin/sh


# 

function write_status {
  echo $1 $2 >&3
}

write_status 'run'  "just started"
sleep 2
echo "TESTTESTTEST"
write_status 'run' "a little after just started"
sleep 2

pwd

env

lsof -p $$

write_status 'run' "post lsof"

write_status 'run' "sleeping 5"
sleep 1

write_status 'run' "sleeping 4"
sleep 1

write_status 'run' "sleeping 3"
sleep 1

write_status 'run' "sleeping 2"
sleep 1

write_status 'run' "sleeping 1"
sleep 1


write_status 'run' "done sleeping"



if [ "$RQ_PARAM1" == "err" ]; then
  echo "This script should end up with err status"
  write_status 'err' "by design"
  exit 0
fi

if [ "$RQ_PARAM1" == "sneaky" ]; then
  echo "This script should *still* end up with err status"
  write_status 'done' "sneaky non zero-exit"
  exit 1
fi

echo "done"
write_status 'done' "done sleeping"


