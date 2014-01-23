#!/bin/bash
# This is a test queue script to make sure that a queue which has custom env vars works correctly
# See test/fixtures/jsonconfigfile/good_env_var.json for the configuration
function write_status {
  echo $1 $2 >&3
}

if [[ "$RQTESTENV1" == "OWEN" ]] && [[ "$RQTESTENV2" == "32" ]]; then
  write_status 'done' "Env var test successful!"
  exit 0
fi

write_status 'err' "Env var test failed!"
