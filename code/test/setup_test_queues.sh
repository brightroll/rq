#!/bin/bash

# SETUP THE QUEUES FOR A VALID TEST
# we are using bash now since Ruby pthreads just don't
# work correctly with fork

echo "Stopping..."
ruby ./code/queuemgr_ctl.rb stop
echo "Stopped..."

echo "Removing installation dirs"
rm -rf './queue.noindex'
rm -rf './queue'
rm -rf './config'

echo "Checking that system is ready for install..."
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

egrep "Please fill out this form in order to setup this RQ\." _home.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system is still in an installed state"
  exit 1
fi

echo "Starting install..."
curl -0 http://127.0.0.1:${rq_port}/install -sL -F install[host]=127.0.0.1 -F install[port]=3333 -F install[addr]=0.0.0.0 -F install[env]=test -o _install.txt
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ failed to respond correctly"
  exit 1
fi

egrep "Your app is now setup\." _install.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system is still in an installed state"
  exit 1
fi

while [ ! -f ./queue/relay/queue.pid ] ; do
  sleep 1
done

echo "Checking that system is operational..."
curl -0 -sL -o _home.txt http://127.0.0.1:${rq_port}/
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ is not running"
  exit 1
fi

sleep 1

egrep "QUEUE MGR is OPERATIONAL" _home.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system is not running the queue mgr"
  exit 1
fi


echo "Creating the test queue..."
curl -0 http://127.0.0.1:${rq_port}/new_queue -sL -F queue[name]=test -F queue[script]=./code/test/test_script.sh -F queue[num_workers]=1 -F queue[coalesce]=no -o _install_test.txt
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ failed to respond correctly"
  exit 1
fi

egrep "successqueue created" _install_test.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system didn't create test queue"
  exit 1
fi

echo "Creating the test coalesce queue..."
curl -0 http://127.0.0.1:${rq_port}/new_queue -sL -F queue[name]=test_coalesce -F queue[script]=./code/test/test_script.sh -F queue[num_workers]=1 -F queue[coalesce]=yes -F queue[coalesce_param1]=1 -o _install_test_coalesce.txt
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ failed to respond correctly"
  exit 1
fi

egrep "successqueue created" _install_test_coalesce.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system didn't create test_coalesce queue"
  exit 1
fi

echo "Creating the test run queue..."
curl -0 http://127.0.0.1:${rq_port}/new_queue -sL -F queue[name]=test_run -F queue[script]=./code/test/test_script.sh -F queue[num_workers]=3 -o _install_test_run.txt
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ failed to respond correctly"
  exit 1
fi

egrep "successqueue created" _install_test_run.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system didn't create test_run queue"
  exit 1
fi

rm _home.txt
rm _install.txt
rm _install_test.txt
rm _install_test_coalesce.txt
rm _install_test_run.txt

echo "ALL DONE SUCCESSFULLY"

