#!/bin/bash

# Send multiple messages to a queue in order to cause a collision
# This is system and performance dependent, so it will rarely fail 
# on laptops of the year 2010


RETURN_VAR=      # BASH IS SOOOOOOO AWESOMEST

function send_msg() {
  local out=`./bin/rq sendmesg  --dest test --src dru4 --relay-ok --param1=done`
  if [ "$?" -ne "0" ]; then
    echo "Sorry, system didn't create test message properly"
    exit 1
  fi

  local result=(${out})

  if [ "${result[0]}" != "ok" ]; then
    echo "Sorry, system didn't create test message properly : ${out}"
    exit 1
  fi

  echo "Queued message: ${result[1]}"

  RETURN_VAR=${result[1]}
  return
}


function verify_msg()
{
  ## Verify that script goes to done state

  local COUNTER=0
  while [  $COUNTER -lt 4 ]; do

    local out3=`./bin/rq statusmesg  --msg_id $1`
    if [ "$?" -ne "0" ]; then
        echo "Sorry, system didn't get status of test message properly"
        exit 1
    fi

    local stat_result=(${out3})
    if [ "${stat_result[0]}" != "ok" ]; then
        echo "Sorry, system didn't get status message properly : ${out3}"
        exit 1
    fi

    if [ "${out3}" == "ok done - done sleeping" ]; then
        echo "Message ${out3} went into proper state. ALL DONE"
        return
    fi

    let COUNTER=COUNTER+1
    sleep 1
  done

  echo "Sorry, system didn't get go to done state properly : ${out3}"
  exit 1
}

send_msg 1
msg1=$RETURN_VAR

send_msg 1
msg2=$RETURN_VAR

send_msg 1
msg3=$RETURN_VAR

send_msg 1
msg4=$RETURN_VAR

send_msg 1
msg5=$RETURN_VAR

send_msg 1
msg6=$RETURN_VAR

verify_msg $msg1
verify_msg $msg2
verify_msg $msg3
verify_msg $msg4
verify_msg $msg5
verify_msg $msg6

echo "SUCCESS - system processed all messages properly"
exit 0
