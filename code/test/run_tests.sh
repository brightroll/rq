#!/bin/bash

# Send the test queue a test message that should end up in done

if [ ! -d "./code" ] ; then
  echo "Must run from 'rq' directory as ./code/test/run_tests.sh"
  exit 1
fi

echo "Running ./code/test/setup_test_queues.sh"
./code/test/setup_test_queues.sh
if [ $? -ne 0 ] ; then
  echo " *** FAILED TO RUN SETUP"
  exit 1
fi

echo "Running ./code/test/test_queues_setup.rb"
./code/test/test_queues_setup.rb
if [ $? -ne 0 ] ; then
  echo " *** FAILED TO SETUP QUEUES"
  exit 1
fi


for test in \
   send_test_coalesce.sh \
   send_test_sneaky.sh \
   test_que_create_naming.sh \
   test_run_admin_down.sh \
   test_run_msgs_moved_on_kill.rb \
   test_hashdir.rb \
   send_test_large.sh \
   send_test_web_done.rb \
   send_test_web_prepattachdone.rb \
   send_test_web_prepattachdone_large.rb \
   send_test_attachdone.sh \
   send_test_cloneattachdone.sh \
   send_test_web_prepdone.rb \
   send_test_done.sh \
   send_test_err.sh  \
   send_test_fast_collide.sh  \
   send_test_relay_force.sh \
   send_test_relay.sh \
   send_test_remote_relay_force.sh \
   send_test_remote_relay_force_large.sh \
   send_test_remote_relay.sh \
   send_test_relay_relayid_attach.sh \
   send_test_relay_relayid.sh \
   send_test_resend.sh ; do

      echo "RUNNING TEST: ${test}"
      output=`./code/test/$test 2>&1`
      status=$?
      echo "$output" | sed "s/^/${test}: /g"
      echo -n "        TEST: "
      if [ $status -ne 0 ] ; then
         echo " *** FAILED ***"
         exit 1
      fi
      echo " PASSED"
done


echo "-=-=-=-=-=-=-=-=-"
echo " ALL TESTS DONE  "
echo "-=-=-=-=-=-=-=-=-"
