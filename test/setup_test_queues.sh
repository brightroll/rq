#!/bin/bash

echo "Checking that system is ready for install..."
if [ "x${RQ_PORT}" = "x" ] ; then
  rq_port=3333
else
  rq_port=${RQ_PORT}
fi

echo "Checking that system is operational..."
curl -0 -sL -o _home.txt http://127.0.0.1:${rq_port}/
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ is not running"
  exit 1
fi

egrep "QUEUE MGR is OPERATIONAL" _home.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system is not running the queue mgr"
  exit 1
fi

# Remove the test queues before trying to create them
rm -fr queue/test
rm -fr queue/test_symlink
rm -fr queue/test_coalesce
rm -fr queue/test_blocking
rm -fr queue/test_run
rm -fr queue/test_nop
rm -fr queue/test_ansi
rm -fr queue/test_env_var
rm -fr queue/test_change

echo "Creating the test queue..."
curl -0 --cookie-jar ./cookie_jar  http://127.0.0.1:${rq_port}/new_queue -sL -F queue[name]=test -F queue[script]=./test/test_script.sh -F queue[num_workers]=1 -F queue[exec_prefix]="" -o _install_test.txt
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ failed to respond correctly"
  exit 1
fi

egrep "queue created" _install_test.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system didn't create test queue"
  exit 1
fi

echo "Creating the test symlink queue..."
curl -0 --cookie-jar ./cookie_jar  http://127.0.0.1:${rq_port}/new_queue -sL -F queue[name]=test_symlink -F queue[script]=./test/test_symlink/test_script_symlink.sh -F queue[num_workers]=1 -F queue[exec_prefix]="" -o _install_test_symlink.txt
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ failed to respond correctly"
  exit 1
fi

egrep "queue created" _install_test_symlink.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system didn't create test_symlink queue"
  exit 1
fi

echo "Creating the test coalesce queue..."
curl -0 --cookie-jar ./cookie_jar http://127.0.0.1:${rq_port}/new_queue -sL -F queue[name]=test_coalesce -F queue[script]=./test/test_script.sh -F queue[num_workers]=1 -F queue[coalesce_params][]=1 -F queue[exec_prefix]="" -o _install_test_coalesce.txt
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ failed to respond correctly"
  exit 1
fi

egrep "queue created" _install_test_coalesce.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system didn't create test_coalesce queue"
  exit 1
fi

echo "Creating the test blocking queue..."
curl -0 --cookie-jar ./cookie_jar http://127.0.0.1:${rq_port}/new_queue -sL -F queue[name]=test_blocking -F queue[script]=./test/test_blocking_script.rb -F queue[num_workers]=3 -F queue[blocking_params][]=1 -F queue[exec_prefix]="" -o _install_test_blocking.txt
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ failed to respond correctly"
  exit 1
fi

egrep "queue created" _install_test_blocking.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system didn't create test_blocking queue"
  exit 1
fi

echo "Creating the test run queue..."
curl -0 --cookie-jar ./cookie_jar http://127.0.0.1:${rq_port}/new_queue -sL -F queue[name]=test_run -F queue[script]=./test/test_script.sh -F queue[num_workers]=3 -F queue[exec_prefix]="" -o _install_test_run.txt
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ failed to respond correctly"
  exit 1
fi

egrep "queue created" _install_test_run.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system didn't create test_run queue"
  exit 1
fi

echo "Creating the test nop queue..."
curl -0 --cookie-jar ./cookie_jar http://127.0.0.1:${rq_port}/new_queue -sL -F queue[name]=test_nop -F queue[script]=./test/test_nop.sh -F queue[num_workers]=1 -F queue[exec_prefix]="" -o _install_test_nop.txt
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ failed to respond correctly"
  exit 1
fi

echo "Creating the ansi test queue..."
curl -0 --cookie-jar ./cookie_jar http://127.0.0.1:${rq_port}/new_queue -sL -F queue[name]=test_ansi -F queue[script]=./test/ansi_script.sh -F queue[num_workers]=1 -F queue[exec_prefix]="" -o _install_ansi_script.txt
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ failed to respond correctly"
  exit 1
fi

egrep "queue created" _install_test_nop.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system didn't create test_nop queue"
  exit 1
fi

echo "Creating the test_env_var test queue..."
curl -0 --cookie-jar ./cookie_jar http://127.0.0.1:${rq_port}/new_queue_link -sL -F queue[json_path]=./test/fixtures/jsonconfigfile/good_env_var.json -o _install_env_var_script.txt
if [ "$?" -ne "0" ]; then
  echo "Sorry, web server for RQ failed to respond correctly"
  exit 1
fi

egrep "queue created" _install_env_var_script.txt > /dev/null
if [ "$?" -ne "0" ]; then
  echo "Sorry, system didn't create test_env_var queue"
  exit 1
fi

rm _home.txt
rm _install.txt
rm _install_test.txt
rm _install_test_symlink.txt
rm _install_test_coalesce.txt
rm _install_test_blocking.txt
rm _install_test_run.txt
rm _install_test_nop.txt
rm _install_ansi_script.txt
rm _install_env_var_script.txt
rm cookie_jar

echo "ALL DONE SUCCESSFULLY"
