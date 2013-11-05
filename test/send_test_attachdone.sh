#!/bin/bash

# Send the test queue a test message that should end up in done

out=`./bin/rq prepmesg  --dest test --src dru4 --relay-ok --param1=done`
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

out1=`./bin/rq attachmesg  --msg_id ${result[1]} --pathname test/fixtures/studio3.jpg`
if [ "$?" -ne "0" ]; then
    echo "Sorry, system didn't commit test message properly"
    exit 1
fi

result1=(${out1})

if [ "${result1[0]}" != "ok" ]; then
    echo "Sorry, system didn't attach to test message properly : ${out1}"
    exit 1
fi

expected="ok 14a1a7845cc7f981977fbba6a60f0e42-Attached successfully for Message: ${result[1]} attachment"
if [ "${out1}" != "${expected}" ]; then
    echo "Attach operation didn't get proper resulting message"
    echo "Got:"
    echo "${out1}"
    echo "Expected:"
    echo "${expected}"
    exit 1
fi

out2=`./bin/rq commitmesg  --msg_id ${result[1]}`
if [ "$?" -ne "0" ]; then
    echo "Sorry, system didn't commit test message properly"
    exit 1
fi

echo "Queued message: ${result[1]}"


## Verify that script goes to done state

COUNTER=0
while [  $COUNTER -lt 4 ]; do

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
        echo "Message went into proper state. ALL DONE"
        exit 0
    fi

    let COUNTER=COUNTER+1
    sleep 1
done


echo "FAIL - system didn't get a message in proper state: ${out3}"
exit 1
