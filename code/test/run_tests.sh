#!/bin/bash

# Send the test queue a test message that should end up in done


echo "Must run from 'rq' directory as ./code/test/run_tests.sh"


echo "To clean the system, run this command first: ./code/test/setup_test_queues.sh"

for test in \
   send_test_sneaky.sh \
   send_test_web_done.rb \
   send_test_web_prepattachdone.rb \
   send_test_web_prepattachdone_large.rb \
   send_test_attachdone.sh \
   send_test_web_prepdone.rb \
   send_test_done.sh \
   send_test_err.sh  \
   send_test_relay_force.sh \
   send_test_relay.sh \
   send_test_remote_relay_force.sh \
   send_test_remote_relay_force_large.sh \
   send_test_remote_relay.sh \
   send_test_resend.sh  ; do

      output=`./code/test/$test 2>&1`
      status=$?
      echo "$output" | sed "s/^/${test}: /g"
      if [ $status -ne 0 ] ; then
         exit 1
      fi
done


echo "-=-=-=-=-=-=-=-=-"
echo " ALL TESTS DONE  "
echo "-=-=-=-=-=-=-=-=-"
