#!/bin/sh

# Send the test queue a test message that should end up in done

out=`./bin/rq prepmesg  --dest http://localhost:3333/q/test --src dru4 --relay-ok --param1=done`
if [ "$?" -ne "0" ]; then
  echo "Sorry, system didn't create test message properly"
  exit 1
fi
result=(${out})
if [ "${result[0]}" != "ok" ]; then
  echo "Sorry, system didn't create test message properly : ${result[0]}"
  exit 1
fi

echo "Prepped message: ${result[1]}"


out2=`./bin/rq commitmesg  --msg_id ${result[1]}`
if [ "$?" -ne "0" ]; then
  echo "Sorry, system didn't commit test message properly"
  exit 1
fi

echo "Queued message: ${result[1]}"

