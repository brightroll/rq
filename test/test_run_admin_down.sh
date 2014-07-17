#!/bin/bash

RETURN_VAR=      # BASH IS SOOOOOOO AWESOMEST

if [ "x${RQ_PORT}" = "x" ] ; then
  rq_port=3333
else
  rq_port=${RQ_PORT}
fi

function send_msg() {
  local due=$((`date +%s` ${1}))
  local out=`./bin/rq sendmesg  --dest test --src dru4 --relay-ok --param1=fast  --due=${due}`
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
  local out=`./bin/rq sendmesg  --dest test --src dru4 --relay-ok --param1=x${due}x --param2=blah --param3=foo --param4=hunoz --due=${due}`
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
  local out=`./bin/rq sendmesg  --dest test --src dru4 --relay-ok --param1=fast  --param2=err --due=${due}`
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
  local out=`./bin/rq sendmesg  --dest test --src dru4 --relay-ok --param1=fast  --param2=resend1 --due=${due}`
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


echo "SETTING admin DOWN"
echo "TEST que in proper DOWN mode"
touch "./config/test.down"

# Verify nothing in run and all in que
curl -0 -sL -o _test.txt http://127.0.0.1:${rq_port}/q/test.txt
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ is not running/couldn't get /q/test.txt"
  exit 1
fi
egrep "status: DOWN" _test.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system has incorrect status - should be DOWN"
  exit 1
fi

echo "TEST que in proper DOWN mode"
echo "SETTING admin UP"

# Set que to admin up and kick scheduler (asking for status is a kick)
rm "./config/test.down"
curl -0 -sL -o _test2.txt http://127.0.0.1:${rq_port}/q/test.txt
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ is not running/couldn't get /q/test.txt"
  exit 1
fi
egrep "status: UP" _test2.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system has incorrect status - should be UP"
  exit 1
fi

rm "_test.txt"
rm "_test2.txt"

echo "SUCCESS - system processed all messages properly"
exit 0
