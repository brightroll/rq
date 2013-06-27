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
rm -fr queue/test_run
rm -fr queue/test_nop
rm -fr queue/test_ansi

echo "Creating the test queue..."
res=$(curl -0 -s -w %{http_code} http://127.0.0.1:${rq_port}/new_queue -F queue[name]=test -F queue[script]=./test/test_script.sh -F queue[num_workers]=1 -F queue[coalesce]=no -F queue[exec_prefix]="")
if [ "$res" -ne "303" ]; then
  echo "Sorry, system didn't create test queue"
  exit 1
fi

echo "Creating the test symlink queue..."
res=$(curl -0 -s -w %{http_code} http://127.0.0.1:${rq_port}/new_queue -F queue[name]=test_symlink -F queue[script]=./test/test_symlink/test_script_symlink.sh -F queue[num_workers]=1 -F queue[coalesce]=no -F queue[exec_prefix]="")
if [ "$res" -ne "303" ]; then
  echo "Sorry, system didn't create test_symlink queue"
  exit 1
fi

echo "Creating the test coalesce queue..."
res=$(curl -0 -s -w %{http_code} http://127.0.0.1:${rq_port}/new_queue -F queue[name]=test_coalesce -F queue[script]=./test/test_script.sh -F queue[num_workers]=1 -F queue[coalesce]=yes -F queue[coalesce_param1]=1 -F queue[exec_prefix]="")
if [ "$res" -ne "303" ]; then
  echo "Sorry, system didn't create test_coalesce queue"
  exit 1
fi

echo "Creating the test run queue..."
res=$(curl -0 -s -w %{http_code} http://127.0.0.1:${rq_port}/new_queue -F queue[name]=test_run -F queue[script]=./test/test_script.sh -F queue[num_workers]=3 -F queue[exec_prefix]="")
if [ "$res" -ne "303" ]; then
  echo "Sorry, system didn't create test_run queue"
  exit 1
fi

echo "Creating the test nop queue..."
res=$(curl -0 -s -w %{http_code} http://127.0.0.1:${rq_port}/new_queue -F queue[name]=test_nop -F queue[script]=./test/test_nop.sh -F queue[num_workers]=1 -F queue[exec_prefix]="")
if [ "$res" -ne "303" ]; then
  echo "Sorry, system didn't create test_nop queue"
  exit 1
fi

echo "Creating the ansi test queue..."
res=$(curl -0 -s -w %{http_code} http://127.0.0.1:${rq_port}/new_queue -F queue[name]=test_ansi -F queue[script]=./test/ansi_script.sh -F queue[num_workers]=1 -F queue[exec_prefix]="")
if [ "$res" -ne "303" ]; then
  echo "Sorry, system didn't create test_ansi queue"
  exit 1
fi

echo "Creating the test_env_var test queue..."
res=$(curl -0 -s -w %{http_code} http://127.0.0.1:${rq_port}/new_queue_link -F queue[json_path]=./test/fixtures/jsonconfigfile/good_env_var.json)
if [ "$res" -ne "303" ]; then
  echo "Sorry, system didn't create test_env_var queue"
  exit 1
fi

rm _home.txt

echo "ALL DONE SUCCESSFULLY"
