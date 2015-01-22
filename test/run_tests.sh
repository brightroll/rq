#!/bin/bash
start_time=$(date +%s)

# Use an alternate port so we don't interfere with real RQ on this host
# Vary the port by Ruby version so that we can run multiple tests at once
export RQ_PORT=33$(ruby -e 'puts RUBY_VERSION.delete(".")')

./bin/rq-mgr stop
./bin/rq-install --force --host 127.0.0.1 --port $RQ_PORT --tmpdir '/tmp'
./bin/rq-mgr start

sleep 1

# Clean up the running RQ at exit
trap './bin/rq-mgr stop' EXIT
trap './bin/rq-mgr stop' TERM
trap './bin/rq-mgr stop' QUIT

# TODO: Consolidate these two scripts
echo "Running ./test/setup_test_queues.sh"
./test/setup_test_queues.sh
if [ $? -ne 0 ] ; then
  echo " *** FAILED TO RUN SETUP"
  exit 1
fi

echo "Running ./test/test_queues_setup.rb"
./test/test_queues_setup.rb
if [ $? -ne 0 ] ; then
  echo " *** FAILED TO SETUP QUEUES"
  exit 1
fi

passed=0
failed=0

# The first block are unit tests, the rest are functional tests
# FIXME: this test hangs: test_run_msgs_moved_on_kill.rb
for test in \
   test_adminoper.rb \
   test_config_change.rb \
   test_hashdir.rb \
   test_overrides.rb \
   test_rule_processor.rb \
   test_message_blocking.rb \
   \
   test_rq.sh \
   send_test_coalesce.sh \
   send_test_sneaky.sh \
   send_test_symlink.sh \
   test_que_create_naming.sh \
   test_run_admin_down.sh \
   test_run_admin_pause.sh \
   send_test_large.sh \
   send_test_web_done.rb \
   send_test_web_prepattachdone.rb \
   send_test_web_http11_prepattachdone.rb \
   send_test_web_prepattachdone_large.rb \
   send_test_web_prepattachmime.rb \
   send_test_attachdone.sh \
   send_test_cloneattachdone.sh \
   send_test_web_prepdone.rb \
   send_test_done.sh \
   send_test_err.sh  \
   send_test_donequick.sh \
   send_test_errquick.sh  \
   send_test_fast_collide.sh  \
   send_test_relay_force.sh \
   send_test_relay.sh \
   send_test_remote_relay_force.sh \
   send_test_remote_relay_force_large.sh \
   send_test_remote_relay.sh \
   send_test_relay_relayid_attach.sh \
   send_test_relay_relayid.sh \
   send_test_resend.sh \
   send_test_force_remote.sh \
   test_web_attach_err.rb \
   test_web_max_count.rb \
   test_web_overrides.rb \
   send_dup.rb \
   test_web_done_json.rb \
   env_var_test.rb ; do

      echo "RUNNING TEST: ${test}"
      output=`./test/$test 2>&1`
      status=$?
      echo "$output" | sed "s/^/${test}: /g"
      echo -n "        TEST: "
      if [ $status -ne 0 ] ; then
         echo " *** FAILED ***"
         failed=$(($failed+1))
      else
         echo " PASSED"
         passed=$(($passed+1))
      fi
done

end_time=$(date +%s)
time_elapsed=$(($end_time-$start_time))
echo "Script execution took $time_elapsed seconds."

./bin/rq-mgr stop

echo "-=-=-=-=-=-=-=-=-"
echo " ALL TESTS DONE  "
echo "-=-=-=-=-=-=-=-=-"
echo "PASSED: ${passed} FAILED: ${failed}"

if [ $failed -ne 0 ]; then
  exit 1
fi
