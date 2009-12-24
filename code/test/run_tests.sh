#!/bin/bash

# Send the test queue a test message that should end up in done


# Break on any non-zero exit (aka - failure)
set -e

echo "Must run from 'rq' directory as ./code/test/run_tests.sh"


echo "To clean the system, run this command first: ./code/test/setup_test_queues.sh"


./code/test/send_test_sneaky.sh
./code/test/send_test_web_done.rb
./code/test/send_test_web_prepattachdone.rb
./code/test/send_test_attachdone.sh
./code/test/send_test_web_prepdone.rb
./code/test/send_test_done.sh
./code/test/send_test_err.sh
./code/test/send_test_relay.sh
./code/test/send_test_remote_relay.sh
./code/test/send_test_resend.sh              


echo "-=-=-=-=-=-=-=-=-"
echo " ALL TESTS DONE  "
echo "-=-=-=-=-=-=-=-=-"
