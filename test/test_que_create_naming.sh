#!/bin/bash

# TEST CANNOT CREATE QUEUES WITH BAD NAMES

echo "Checking that system is ready for que setup install..."
if [ "x${RQ_PORT}" = "x" ] ; then
  rq_port=3333
else
  rq_port=${RQ_PORT}
fi

curl -0 -sL -o _home.txt http://127.0.0.1:${rq_port}/
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ is not running"
  exit 1
fi
egrep -v "Please fill out this form in order to setup this RQ\." _home.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system is still in install state"
  exit 1
fi
egrep "QUEUE MGR is OPERATIONAL" _home.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system is not running the queue mgr"
  exit 1
fi


echo "Attempting to create a queue with a space in name"
res=$(curl -0 -s -w %{http_code} -o /dev/null http://127.0.0.1:${rq_port}/new_queue -F queue[name]='bad que test' -F queue[script]=./test/test_script.sh -F queue[num_workers]=1 -F queue[coalesce]=no)
if [ "$res" -ne "400" ]; then
  echo "Sorry, system created bad queue 'bad que test' queue"
  exit 1
fi

echo "Attempting to create a queue with a '.' in name"
res=$(curl -0 -s -w %{http_code} -o /dev/null http://127.0.0.1:${rq_port}/new_queue -F queue[name]='bad.que.test' -F queue[script]=./test/test_script.sh -F queue[num_workers]=1 -F queue[coalesce]=no)
if [ "$res" -ne "400" ]; then
  echo "Sorry, system created bad queue 'bad.que.test' queue"
  exit 1
fi

echo "Attempting to create a queue with a '/' in name"
res=$(curl -0 -s -w %{http_code} -o /dev/null http://127.0.0.1:${rq_port}/new_queue -F queue[name]='bad/que/test' -F queue[script]=./test/test_script.sh -F queue[num_workers]=1 -F queue[coalesce]=no)
if [ "$?" -ne "0" ]; then
  echo "Sorry, system created bad queue 'bad/que/test' queue"
  exit 1
fi

rm _home.txt

echo "ALL DONE SUCCESSFULLY"
