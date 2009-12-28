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
curl -sL -o _home.txt http://127.0.0.1:3333/
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ is not running"
  exit 1
fi

egrep "Your app is not setup\." _home.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system is still in an installed state"
  exit 1
fi

echo "Starting install..."
curl http://127.0.0.1:3333/install -sL -F dummy=dummy  -o _install.txt
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ failed to respond correctly"
  exit 1
fi

egrep "Your app is now setup\." _install.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system is still in an installed state"
  exit 1
fi

echo "Starting queuemgr..."
ruby ./code/queuemgr_ctl.rb start
sleep 1
echo "Started queuemgr..."

echo "Checking that system is operational..."
curl -sL -o _home.txt http://127.0.0.1:3333/
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ is not running"
  exit 1
fi

egrep "QUEUE MGR is OPERATIONAL" _home.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system is not running the queue mgr"
  exit 1
fi


# CREATE THE RELAY QUE

echo "Creating the relay queue..."
curl http://127.0.0.1:3333/new_queue -sL -F queue[url]=http://localhost:3333/ -F queue[name]=relay -F queue[script]=./code/relay_script.rb -F queue[ordering]=ordered -F queue[num_workers]=1 -F queue[fsync]=fsync -o _install_relay.txt
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ failed to respond correctly"
  exit 1
fi

egrep "successqueue created" _install_relay.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system didn't create relay queue"
  exit 1
fi


echo "Creating the test queue..."
curl http://127.0.0.1:3333/new_queue -sL -F queue[url]=http://localhost:3333/ -F queue[name]=test -F queue[script]=./code/test/test_script.sh -F queue[ordering]=ordered -F queue[num_workers]=1 -F queue[fsync]=fsync -o _install_test.txt
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ failed to respond correctly"
  exit 1
fi

egrep "successqueue created" _install_test.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system didn't create test queue"
  exit 1
fi

rm _home.txt
rm _install.txt
rm _install_relay.txt
rm _install_test.txt

echo "ALL DONE SUCCESSFULLY"

