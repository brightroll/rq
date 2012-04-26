#!/bin/bash

# Send the test queue a test message that should end up in done

out=`./bin/rq prepmesg  --dest test --src dru4 --relay-ok --param1=err`
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


## Verify that script goes to err state

COUNTER=0
while [  $COUNTER -lt 4 ]; do

    out3=`./bin/rq state --msg_id ${result[1]}`
    if [ "$?" -ne "0" ]; then
        echo "Sorry, system didn't get exit status of state of test message properly"
        exit 1
    fi

    stat_result=(${out3})
    if [ "${stat_result[0]}" != "ok" ]; then
        echo "Sorry, system didn't get state message properly : ${out3}"
        exit 1
    fi

    if [ "${out3}" == "ok err" ]; then
        echo "Message went into proper state (err). ALL DONE"
        exit 0
    fi

    let COUNTER=COUNTER+1
    sleep 1
done


echo "FAIL - system didn't get a message in proper state: ${out3}"
exit 1
