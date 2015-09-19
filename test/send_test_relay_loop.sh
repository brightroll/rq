#!/bin/bash

# Send a relay-able message

if [ "x${RQ_PORT}" = "x" ] ; then
    rq_port=3333
else
    rq_port=${RQ_PORT}
fi

out=`./bin/rq prepmesg  --dest http://127.0.0.1:${rq_port}/q/relay --src dru4 --relay-ok --param1=done`
if [ "$?" -ne "0" ]; then
    echo "Sorry, system didn't create test message properly"
    exit 1
fi

result=(${out})

if [ "${result[0]}" != "ok" ]; then
    echo "Sorry, system didn't create test message properly : ${out}"
    exit 1
fi

echo "Prepped message: ${result[1]}"


out2=`./bin/rq commitmesg  --msg_id ${result[1]}`
if [ "$?" -ne "0" ]; then
    echo "Sorry, system didn't commit test message properly"
    exit 1
fi

echo "Queued message: ${result[1]}"


COUNTER=0
while [  $COUNTER -lt 8 ]; do

    out3=`./bin/rq statusmesg  --msg_id ${result[1]}`
    if [ "$?" -ne "0" ]; then
        echo "Sorry, system didn't get status of test message properly"
        exit 1
    fi

    if [ "${out3}" == "ok err - Relay loop detected: RQ_DEST queue same as RQ_ORIG_MSG_ID" ]; then
        echo "Relay loop was detected correctly: ${out3}"
        exit 0
    fi

    let COUNTER=COUNTER+1
    sleep 1
done

echo "Timed out waiting for message to be processed."
exit 1
