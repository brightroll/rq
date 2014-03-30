#!/bin/bash

function write_status {
  echo $1 $2 >&3
}


RETURN_VAR=      # BASH IS SOOOOOOO AWESOMEST

function read_status() {
  # read line from fd4 into result
  read -u 4 readresult

  if [ "$?" -ne "0" ]; then
    echo "Sorry, system didn't read response correctly"
    exit 1
  fi

  RETURN_VAR=(${readresult})

  return
}



write_status 'run'  "just started"
echo "TESTTESTTEST"
write_status 'run' "a little after just started"
#sleep 1

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

if [ "$RQ_PARAM1" == "dup_relay" ]; then
  # Todo: need something better than a free roaming rm
  rm -f "$RQ_PARAM2"
  echo "This script should create a duplicate to the test_nop queue"
  write_status 'run' "start dup"
  # Bash syntax to remove a trailing slash if present: ${variable%/}
  write_status 'dup' "0-X-${RQ_HOST%/}/q/test_nop"
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


