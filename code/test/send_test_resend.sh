#!/bin/bash

# Send the test queue a test message that should end up in done

out=`./bin/rq prepmesg  --dest test --src dru4 --relay-ok --param1=resend1`
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


## Verify that script goes to done state

COUNTER=0
while [  $COUNTER -lt 8 ]; do

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

    if [ "${out3}" == "ok done - done sleeping" ]; then
        #echo "Message went into proper state. break"
        break
    fi

    let COUNTER=COUNTER+1
    sleep 1
done


out4=`./bin/rq statuscountmesg  --msg_id ${result[1]}`
if [ "$?" -ne "0" ]; then
    echo "Sorry, system didn't get status of test message properly"
    exit 1
fi

count_result=(${out4})
if [ "${count_result[0]}" != "ok" ]; then
    echo "Sorry, system didn't get status count message properly : ${out4}"
    exit 1
fi

if [ "${out4}" == "ok 1" ]; then
    echo "Message had proper resend count. ALL DONE"
    exit 0
fi

