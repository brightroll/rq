#!/bin/bash

# Test the force_remote option
# It should send a message that would definitely be considered local, but
# still queue it in the relay regardless

RETURN_VAR=      # BASH IS SOOOOOOO AWESOMEST


if [ "x${RQ_PORT}" = "x" ] ; then
  rq_port=3333
else
  rq_port=${RQ_PORT}
fi

function send_msg() {
  local out=`./bin/rq sendmesg  --dest http://127.0.0.1:${rq_port}/q/test --src dru4 --relay-ok --param1=done --force_remote`
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

function verify_relay()
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

    if [ "${stat_result[1]}" == "relayed" ]; then
        echo "Message ${out3} went into proper state."
        new_mesg_id="${stat_result[3]}"
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

echo "Message went into proper state."
verify_relay $msg1

# verify that it was considered a remote delivery
echo "Checking remote delivery"
curl -0 -sL -o _test_force.txt ${msg1}/log/stdio.log
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ is not running/couldn't get ${msg1}/log/stdio.log"
  exit 1
fi
egrep "FORCE REMOTE" _test_force.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system didn't have 'FORCE REMOTE' in log when doing --force_remote"
  exit 1
fi
egrep "attempting remote " _test_force.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system didn't try remote delivery when doing --force_remote"
  exit 1
fi

# verify that original message has force_remote
echo "Verifying original has force_remote param"
rm _test_force.txt
curl -0 -sL -o _test_force.txt ${msg1}.json
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ is not running/couldn't get ${msg1}.json"
  exit 1
fi
egrep "force_remote" _test_force.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, message didn't have 'force_remote' in msg json when doing --force_remote"
  exit 1
fi

# ...but the relayed message does not have force_remote
echo "Verifying relayed does not have force_remote param"
rm _test_force.txt
curl -0 -sL -o _test_force.txt ${new_mesg_id}.json
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ is not running/couldn't get ${new_mesg_id}.json"
  exit 1
fi
egrep -q "force_remote" _test_force.txt > /dev/null
## NOTE THE 1, WE DON'T WANT TO SEE the "force_remote"
if [ "$?" -ne "1" ]; then
  echo "Sorry, message didn't have 'force_remote' in msg json when doing --force_remote"
  exit 1
fi

rm _test_force.txt

echo "SUCCESS - system sent force_remote properly"
exit 0
