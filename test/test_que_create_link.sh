#!/bin/bash

# TEST CANNOT CREATE QUEUES WITH BAD NAMES

echo "Checking that system is ready for que setup install..."
if [ "x${RQ_PORT}" = "x" ] ; then
  rq_port=3333
else
  rq_port=${RQ_PORT}
fi

rm -rf cookie_jar

curl -0 -sL -o _home.txt http://127.0.0.1:${rq_port}/
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ is not running"
  exit 1
fi
grep -v "Please fill out this form in order to setup this RQ\." _home.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system is still in install state"
  exit 1
fi
grep "QUEUE MGR is OPERATIONAL" _home.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system is not running the queue mgr"
  exit 1
fi


echo "Attempting to create a queue via symlink"
curl -0 --cookie-jar ./cookie_jar http://127.0.0.1:${rq_port}/new_queue_link -s -L -F queue[json_path]=./test/fixtures/que_create/test_config.json -o _install_bad1.txt
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ failed to respond correctly"
  cat _install_bad1.txt
  exit 1
fi

grep "queue created" _install_bad1.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system did not create queue via link"
  exit 1
fi

rm _home.txt
rm _install_bad1.txt
rm cookie_jar

echo "ALL DONE SUCCESSFULLY"

