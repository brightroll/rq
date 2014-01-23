#!/bin/bash

# Send multiple messages to a queue in order to cause a coalesce


RETURN_VAR=      # BASH IS SOOOOOOO AWESOMEST

function send_msg() {
  local due=$((`date +%s` ${1}))
  local out=`./bin/rq sendmesg  --dest test_coalesce --src dru4 --relay-ok --param1=fast  --due=${due}`
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

function send_msg_diff() {
  local due=$((`date +%s` ${1}))
  local out=`./bin/rq sendmesg  --dest test_coalesce --src dru4 --relay-ok --param1=x${due}x --param2=blah --param3=foo --param4=hunoz --due=${due}`
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

function send_msg_err() {
  local due=$((`date +%s` ${1}))
  local out=`./bin/rq sendmesg  --dest test_coalesce --src dru4 --relay-ok --param1=fast  --param2=err --due=${due}`
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

function send_msg_resend() {
  local due=$((`date +%s` ${1}))
  local out=`./bin/rq sendmesg  --dest test_coalesce --src dru4 --relay-ok --param1=fast  --param2=resend1 --due=${due}`
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
  ## Verify that msg goes to done state

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

function verify_msg_err()
{
  ## Verify that msg goes to err state

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

    if [ "${out3}" == "ok err - by design" ]; then
        echo "Message ${out3} went into proper state. ALL DONE"
        return
    fi

    let COUNTER=COUNTER+1
    sleep 1
  done

  echo "Sorry, system didn't get go to done state properly : ${out3}"
  exit 1
}

function verify_msg_dup()
{
  ## Verify that msg goes to done state

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

    echo "expecting: 'ok done - duplicate ${2}'"
    echo "      got: '${out3}'"
    if [ "${out3}" == "ok done - duplicate ${2}" ]; then
        echo "Message ${out3} went into proper state. ALL DONE"
        return
    fi

    let COUNTER=COUNTER+1
    sleep 1
  done

  echo "Sorry, system didn't get go to done state properly : ${out3}"
  exit 1
}


echo "Testing proper coalesce"
# Test successful coalescing
send_msg +3
msg1=$RETURN_VAR

send_msg +3
msg2=$RETURN_VAR

send_msg -2
msg3=$RETURN_VAR

verify_msg $msg3
verify_msg_dup $msg1 $msg3
verify_msg_dup $msg2 $msg3


echo "Testing error coalesce"
# Test coalesce on a message that ends up being an error that
# should re-inject messages back into 'que' state
send_msg +2
msg5=$RETURN_VAR

send_msg +4
msg6=$RETURN_VAR

send_msg_err -2
msg4=$RETURN_VAR

verify_msg_err $msg4
verify_msg $msg5
verify_msg_dup $msg6 $msg5

echo "Testing no coalesce"
# Test coalesce on a messages that have the same param1 but diff param2 
# They should all go to just done
send_msg_diff +2
msg7=$RETURN_VAR

send_msg_diff +3
msg8=$RETURN_VAR

send_msg_diff -1
msg9=$RETURN_VAR

verify_msg $msg7
verify_msg $msg8
verify_msg $msg9

echo "Testing resend coalesce"
# Test coalesce on a message that ends up being a resend
# should re-inject dups of itself back into 'que' state
# and then it should become a dup of another message that is ready
# to run (msg10)

send_msg +2
msg10=$RETURN_VAR

send_msg +3
msg11=$RETURN_VAR

send_msg_resend -2
msg12=$RETURN_VAR

verify_msg $msg10
verify_msg_dup $msg11 $msg10
verify_msg_dup $msg12 $msg10

echo "SUCCESS - system processed all messages properly"
exit 0
