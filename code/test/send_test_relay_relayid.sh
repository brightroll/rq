#!/bin/bash

# Send a relay-able message 

if [ "x${RQ_PORT}" = "x" ] ; then
    rq_port=3333
else
    rq_port=${RQ_PORT}
fi

out=`./bin/rq prepmesg  --dest http://127.0.0.1:${rq_port}/q/test --src dru4 --relay-ok --param1=done --param2=the_mighty_rq_force --param3=fail`
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


## Verify that script goes to relayed state

COUNTER=0
while [  $COUNTER -lt 12 ]; do

    out3=`./bin/rq statusmesg  --msg_id ${result[1]}`
    if [ "$?" -ne "0" ]; then
        echo "Sorry, system didn't get status of test message properly"
        exit 1
    fi

    stat_result=(${out3})
    if [ "${stat_result[0]}" != "ok" ]; then
        echo "Sorry, system didn't get status message properly : ${out3}"
        exit 1
    fi

    #echo "DRU1"
    #echo "${stat_result[1]}"
    #echo "DRU2"
    #echo "${stat_result[2]}"
    #echo "DRU3"
    #echo "${stat_result[3]}"
    #echo
    if [ "${stat_result[1]}" == "relayed" ]; then
        echo "Message went into relayed state. break"
        new_mesg_id="${stat_result[3]}"
        break
    fi

    let COUNTER=COUNTER+1
    sleep 1
done

if [ "${stat_result[1]}" != "relayed" ]; then
    echo "Timed out waiting for message to go into relayed state."
    exit 1
fi

echo "New message id: ${new_mesg_id}"

# Now check on relayed message to see that it is in done state

## Verify that script goes to done state

COUNTER=0
while [  $COUNTER -lt 4 ]; do

    out4=`./bin/rq statusmesg  --msg_id ${new_mesg_id}`
    if [ "$?" -ne "0" ]; then
        echo "Sorry, system didn't get status of test message properly"
        exit 1
    fi

    stat_result=(${out4})
    if [ "${stat_result[0]}" != "ok" ]; then
        echo "Sorry, system didn't get status message properly : ${out4}"
        exit 1
    fi

    if [ "${out4}" == "ok done - done sleeping" ]; then
        echo "Message went into proper state. ALL DONE"
        exit 0
    fi

    let COUNTER=COUNTER+1
    sleep 1
done


echo "FAIL - system didn't get a message in proper state: ${out4}"
exit 1

