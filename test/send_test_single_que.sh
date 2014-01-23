#!/bin/bash

# Test a single_que message

# Send one message to go into run
# Send another immediately afterward to wait in 'que' since slow3 will take 3 secs to finish run
# Send another to verify that we receive the same msg_id back

if [ "x${RQ_PORT}" = "x" ] ; then
    rq_port=3333
else
    rq_port=${RQ_PORT}
fi

# wait for queue to be empty - if this becomes a problem then I will add a loop here as a TODO
# ... more info, some other test script my have something leftover in a que
sleep 1

# Send 1 - Go into run
out=`./bin/rq single_que  --dest test --src dru4 --relay-ok --param1=slow3`
if [ "$?" -ne "0" ]; then
    echo "Sorry, system didn't create test message properly - non zero exit"
    exit 1
fi

result=(${out})

if [ "${result[0]}" != "ok" ]; then
    echo "Sorry, system didn't create test message properly : ${out}"
    echo "Sorry, system didn't create test message properly : ${result[0]}"
    exit 1
fi

echo "Prepped message: ${result[1]}"
# let it go into run (more than enough time)
sleep 1

# Send 2 - Go into que
out=`./bin/rq single_que  --dest test --src dru4 --relay-ok --param1=slow3`
if [ "$?" -ne "0" ]; then
    echo "Sorry, system didn't create test 2 message properly - non zero exit"
    exit 1
fi

result2=(${out})

if [ "${result2[0]}" != "ok" ]; then
    echo "Sorry, system didn't create test 2 message properly : ${out}"
    exit 1
fi

echo "Prepped message: ${result2[1]}"

# Send 3 - Go into que
out=`./bin/rq single_que  --dest test --src dru4 --relay-ok --param1=slow3`
if [ "$?" -ne "0" ]; then
    echo "Sorry, system didn't create test 3 message properly - non zero exit"
    exit 1
fi

result3=(${out})

if [ "${result3[0]}" != "ok" ]; then
    echo "Sorry, system didn't create test 3 message properly : ${out}"
    exit 1
fi

echo "Prepped message: ${result3[1]}"

if [ "${result3[1]}" != "${result2[1]}" ]; then
    echo "Sorry, system didn't get same msg id : ${out}"
    exit 1
fi

echo "Got same message id back - ALL DONE"
exit 0


